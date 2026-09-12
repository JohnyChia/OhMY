const supabase = require("../config/supabase");

async function discoverCommunity(query = "") {
  const safeQuery = String(query).trim();
  try {
    const { data, error } = await supabase.rpc("community_feed", {
      search_query: safeQuery,
      tag_filters: [],
      result_limit: 6,
      result_offset: 0
    });
    if (error) throw error;

    return {
      success: true,
      query: safeQuery,
      posts: (data || []).map((post) => ({
        id: post.id,
        author_name: post.author_name || "Traveller",
        location_name: post.location_name || "",
        attraction_name: post.attraction_name || "",
        description: post.description || "",
        tags: post.tags || [],
        like_count: post.like_count || 0
      }))
    };
  } catch (error) {
    console.warn("Community discovery unavailable:", error.message);
    return {
      success: false,
      query: safeQuery,
      posts: [],
      unavailable: true,
      error: "Community posts are unavailable right now."
    };
  }
}

module.exports = { discoverCommunity };
