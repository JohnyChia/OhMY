const supabase = require("../config/supabase");
const { v4: uuidv4 } = require("uuid");

const memorySessions = new Map();

async function getOrCreateSession(user_id) {
  if (!user_id) {
    throw new Error("user_id missing");
  }

  try {
    const { data, error } = await supabase
      .from("sessions")
      .select("*")
      .eq("user_id", user_id)
      .maybeSingle();

    if (!error && data) {
      return data;
    }

    if (!error) {
      const { data: newSession, error: createError } = await supabase
        .from("sessions")
        .insert({ user_id })
        .select()
        .single();

      if (!createError && newSession) {
        return newSession;
      }
    }
  } catch (err) {
    console.log("Supabase session query exception, using in-memory store:", err.message);
  }

  if (!memorySessions.has(user_id)) {
    memorySessions.set(user_id, {
      id: uuidv4(),
      user_id: user_id,
      created_at: new Date().toISOString()
    });
  }
  return memorySessions.get(user_id);
}

module.exports = {
  getOrCreateSession
};