const supabase = require('../config/supabase');

/**
 * Binds a Nova request to the signed-in Supabase user. The mobile client may
 * include user_id for compatibility, but it is never trusted as identity.
 */
async function requireNovaUser(req, res, next) {
  const header = String(req.get('authorization') || '');
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    return res.status(401).json({ success: false, error: 'Authentication is required.' });
  }

  try {
    const { data, error } = await supabase.auth.getUser(match[1]);
    const user = data?.user;
    if (error || !user?.id) {
      return res.status(401).json({ success: false, error: 'Authentication could not be verified.' });
    }
    if (req.body?.user_id && req.body.user_id !== user.id) {
      return res.status(403).json({ success: false, error: 'Authenticated user does not match request user.' });
    }
    req.novaUserId = user.id;
    if (req.body) req.body.user_id = user.id;
    return next();
  } catch (error) {
    console.warn('Nova authentication check failed:', error.message);
    return res.status(401).json({ success: false, error: 'Authentication could not be verified.' });
  }
}

module.exports = requireNovaUser;
