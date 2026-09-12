import cors from 'cors';
import express, { type NextFunction, type Request, type Response } from 'express';
import type { SupabaseClient } from '@supabase/supabase-js';
import { authenticate, loadRuleData, loadValidationContext } from './database.js';
import { detectLocationTags, reviewPostText } from './nlp.js';
import { getPlaceTypes } from './places.js';

type AuthedRequest = Request & { userId?: string };

export interface AppDependencies {
  database: SupabaseClient;
  googlePlacesApiKey?: string;
  allowedOrigins?: string[];
}

function bodyString(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

function imagePaths(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string') : [];
}

export function createApp(dependencies: AppDependencies) {
  const app = express();
  app.disable('x-powered-by');
  app.use(cors({ origin: dependencies.allowedOrigins?.length ? dependencies.allowedOrigins : false }));
  app.use(express.json({ limit: '128kb' }));

  app.get('/health', (_request, response) => response.json({ ok: true }));

  app.use('/community', async (request: AuthedRequest, response: Response, next: NextFunction) => {
    const header = request.header('authorization') ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
    if (!token) return response.status(401).json({ code: 'UNAUTHENTICATED', reason: 'Please sign in.' });
    try {
      request.userId = await authenticate(dependencies.database, token);
      return next();
    } catch {
      return response.status(401).json({ code: 'UNAUTHENTICATED', reason: 'Your session is invalid or expired.' });
    }
  });

  async function validate(
    request: AuthedRequest,
    contextInput: { historyEntryId?: string; postId?: string },
  ) {
    const context = await loadValidationContext(dependencies.database, request.userId!, contextInput);
    if (!context.eligible) {
      return {
        status: 403,
        body: {
          approved: false,
          code: 'HISTORY_NOT_ELIGIBLE',
          reason: context.reason,
          fieldErrors: {},
        },
      };
    }
    const rules = await loadRuleData(dependencies.database);
    const review = reviewPostText({
      title: bodyString(request.body.title),
      description: bodyString(request.body.description),
      destination: context.destination,
      attraction: context.attraction,
      blockedTerms: rules.blockedTerms,
      allowList: rules.allowList,
      aliases: rules.aliases,
    });
    if (!review.approved) return { status: 422, body: review };

    const placeTypes = await getPlaceTypes(
      context.destination,
      context.attraction,
      dependencies.googlePlacesApiKey,
    );
    const detectedTags = detectLocationTags({
      destination: context.destination,
      attraction: context.attraction,
      placeTypes,
      tags: rules.tags,
      rules: rules.tagRules,
      fallbackTagName: rules.fallbackTagName,
    });
    if (detectedTags.length === 0) {
      return {
        status: 503,
        body: {
          approved: false,
          code: 'TAG_CONFIGURATION_MISSING',
          reason:
            'Google Places did not return a supported location category. Please retry later.',
          fieldErrors: {},
        },
      };
    }
    return { status: 200, body: { ...review, detectedTags }, context };
  }

  app.post('/community/posts', async (request: AuthedRequest, response) => {
    const paths = imagePaths(request.body.imagePaths);
    if (paths.length < 1 || paths.length > 6) {
      return response.status(422).json({ code: 'INVALID_IMAGES', reason: 'Select between 1 and 6 pictures.' });
    }
    try {
      const historyEntryId = bodyString(request.body.historyEntryId);
      const result = await validate(request, { historyEntryId });
      if (result.status !== 200 || !('context' in result)) return response.status(result.status).json(result.body);
      const detectedTags = 'detectedTags' in result.body ? result.body.detectedTags : [];
      const { data, error } = await dependencies.database.rpc('community_create_post_v5', {
        p_user_id: request.userId,
        p_history_entry_id: historyEntryId,
        p_title: bodyString(request.body.title).trim(),
        p_description: bodyString(request.body.description).trim(),
        p_image_paths: paths,
        p_tag_ids: detectedTags.map((tag) => tag.id),
        p_moderation_reason: result.body.reason,
      });
      if (error) throw error;
      return response.status(201).json({ postId: data, detectedTags });
    } catch (error) {
      return response.status(503).json({
        code: 'PUBLISH_UNAVAILABLE',
        reason: 'The post could not be validated and published. Please retry.',
        detail: error instanceof Error ? error.message : String(error),
      });
    }
  });

  app.patch('/community/posts/:postId', async (request: AuthedRequest, response) => {
    const replacements = imagePaths(request.body.imagePaths);
    if (replacements.length > 6) {
      return response.status(422).json({ code: 'INVALID_IMAGES', reason: 'A post can contain up to 6 pictures.' });
    }
    try {
      const postId = String(request.params.postId ?? '');
      const result = await validate(request, { postId });
      if (result.status !== 200 || !('context' in result)) return response.status(result.status).json(result.body);
      const detectedTags = 'detectedTags' in result.body ? result.body.detectedTags : [];
      const { data, error } = await dependencies.database.rpc('community_update_post_v5', {
        p_user_id: request.userId,
        p_post_id: postId,
        p_title: bodyString(request.body.title).trim(),
        p_description: bodyString(request.body.description).trim(),
        p_image_paths: replacements,
        p_tag_ids: detectedTags.map((tag) => tag.id),
        p_moderation_reason: result.body.reason,
      });
      if (error) throw error;
      return response.json({ postId: data, detectedTags });
    } catch (error) {
      return response.status(503).json({
        code: 'UPDATE_UNAVAILABLE',
        reason: 'The changes could not be validated and saved. Please retry.',
        detail: error instanceof Error ? error.message : String(error),
      });
    }
  });

  return app;
}
