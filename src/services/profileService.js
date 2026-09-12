const supabase = require("../config/supabase");

const memoryProfiles = new Map();

async function getProfile(user_id) {
  try {
    const { data, error } = await supabase
      .from("traveler_profiles")
      .select("*")
      .eq("user_id", user_id)
      .maybeSingle();

    if (!error && data) {
      return data;
    }
  } catch (err) {
    console.log("Supabase getProfile exception, using memory fallback:", err.message);
  }

  return memoryProfiles.get(user_id) || {};
}

async function updateProfile(user_id, data) {
  const old = await getProfile(user_id);

  const merged = {
    user_id,
    preferred_language: data.preferred_language
      ? data.preferred_language
      : old.preferred_language ?? null,
    travel_style: data.travel_style
      ? data.travel_style
      : old.travel_style ?? null,
    favorite_categories: Array.isArray(data.favorite_categories)
      ? [
          ...new Set([
            ...(old.favorite_categories || []),
            ...data.favorite_categories
          ])
        ]
      : old.favorite_categories || [],
    budget_preference: data.budget_preference
      ? data.budget_preference
      : old.budget_preference ?? null,
    updated_at: new Date()
  };

  try {
    const { data: result, error } = await supabase
      .from("traveler_profiles")
      .upsert(merged, { onConflict: "user_id" })
      .select()
      .single();

    if (!error && result) {
      memoryProfiles.set(user_id, result);
      return result;
    }
  } catch (err) {
    console.log("Supabase updateProfile exception, saving memory fallback:", err.message);
  }

  memoryProfiles.set(user_id, merged);
  return merged;
}

module.exports = {
  getProfile,
  updateProfile
};