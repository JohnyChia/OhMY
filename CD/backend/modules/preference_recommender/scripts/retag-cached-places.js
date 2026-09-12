require("dotenv").config();

const { createClient } = require("@supabase/supabase-js");
const { TaggingService, GENERAL_TAGS } = require("../tagging-service");
const { analyzePlace } = require("../place-analysis-service");
const {
    storeTaggedPlace,
    buildTagAssignments,
    tagFingerprint
} = require("../place-cache-service");
const { getPlaceDetails } = require("../googlePlacesService");
const { TAGGER_VERSION } = require("../config");

function option(name, fallback = null) {
    const prefix = `--${name}=`;
    const inline = process.argv.find(argument => argument.startsWith(prefix));
    if (inline) return inline.slice(prefix.length);
    const index = process.argv.indexOf(`--${name}`);
    return index >= 0 && process.argv[index + 1]
        ? process.argv[index + 1]
        : fallback;
}

function positiveInteger(value, fallback) {
    const parsed = Number.parseInt(value, 10);
    return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

async function main() {
    const dryRun = process.argv.includes("--dry-run");
    const limit = positiveInteger(option("limit", "100"), 100);
    const afterId = positiveInteger(option("after-id", "0"), 0);
    const fromVersion = option("from-version");
    const url = process.env.SUPABASE_URL;
    const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!url || !serviceKey) {
        throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required.");
    }
    if (!process.env.GOOGLE_PLACES_API_KEY) {
        throw new Error("GOOGLE_PLACES_API_KEY is required.");
    }

    const client = createClient(url, serviceKey, {
        auth: { persistSession: false, autoRefreshToken: false }
    });
    let query = client
        .from("places")
        .select("id,google_place_id,name,tagger_version,tag_fingerprint")
        .gt("id", afterId)
        .order("id", { ascending: true })
        .limit(limit);
    query = fromVersion
        ? query.eq("tagger_version", fromVersion)
        : query.or(`tagger_version.is.null,tagger_version.neq.${TAGGER_VERSION}`);

    const { data: places, error } = await query;
    if (error) throw error;

    const tagger = new TaggingService();
    const summary = {
        selected: places.length,
        processed: 0,
        changed: 0,
        unchanged: 0,
        failed: 0,
        dryRun,
        taggerVersion: TAGGER_VERSION,
        lastId: afterId
    };

    for (const stored of places) {
        summary.lastId = stored.id;
        try {
            const place = await getPlaceDetails(stored.google_place_id);
            const analysis = analyzePlace(place, tagger, GENERAL_TAGS);
            if (dryRun) {
                const fingerprint = tagFingerprint(
                    buildTagAssignments(analysis, GENERAL_TAGS)
                );
                const changed = stored.tag_fingerprint !== fingerprint;
                if (changed) summary.changed++;
                else summary.unchanged++;
                console.log(
                    `[dry-run:${changed ? "changed" : "unchanged"}] `
                    + `${stored.id} ${stored.name}: `
                    + `${analysis.generalTags.length + analysis.culturalTags.length} tags`
                );
                summary.processed++;
                continue;
            }
            const result = await storeTaggedPlace(
                client,
                place,
                analysis,
                TAGGER_VERSION,
                GENERAL_TAGS
            );
            summary.processed++;
            if (result.changed) summary.changed++;
            else summary.unchanged++;
            console.log(
                `[${result.changed ? "changed" : "unchanged"}] `
                + `${stored.id} ${stored.name}`
            );
        } catch (error) {
            summary.failed++;
            console.error(`[failed] ${stored.id} ${stored.name}: ${error.message}`);
        }
    }

    console.log(JSON.stringify(summary, null, 2));
    if (places.length === limit) {
        console.log(`Resume with --after-id ${summary.lastId}`);
    }
}

main().catch(error => {
    if (
        error?.code === "42703"
        && String(error.message || "").includes("tag_fingerprint")
    ) {
        console.error(
            "Tagger V2 has not been migrated in the connected Supabase database.\n"
            + "Apply supabase/migrations/20260912_preference_recommender_tagger_v2.sql "
            + "in the Supabase SQL Editor, then run this command again."
        );
    } else {
        console.error(error);
    }
    process.exitCode = 1;
});
