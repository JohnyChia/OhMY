const supabase = require("../config/supabase");

const memoryMessages = [];

async function saveMessage(user_id, session_id, role, content) {
  try {
    const { data: last } = await supabase
      .from("messages")
      .select("*")
      .eq("session_id", session_id)
      .eq("role", role)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    const { data, error } = await supabase
      .from("messages")
      .insert({
        user_id,
        session_id,
        role,
        content
      })
      .select()
      .single();

    if (!error && data) {
      return data;
    }
  } catch (err) {
    console.log("Supabase saveMessage exception, using memory fallback:", err.message);
  }

  const msgObj = {
    id: Date.now().toString(),
    user_id,
    session_id,
    role,
    content,
    created_at: new Date().toISOString()
  };
  memoryMessages.push(msgObj);
  return msgObj;
}

async function getShortMemory(user_id, session_id) {
  try {
    const { data, error } = await supabase
      .from("messages")
      .select("*")
      .eq("user_id", user_id)
      .eq("session_id", session_id)
      .order("created_at", { ascending: false })
      .limit(6);

    if (!error && data) {
      return data.reverse();
    }
  } catch (err) {
    console.log("Supabase getShortMemory exception, using memory fallback:", err.message);
  }

  const filtered = memoryMessages.filter(
    (m) => m.user_id === user_id && m.session_id === session_id
  );
  return filtered.slice(-6);
}

async function getLongMemory(user_id) {
  try {
    const { data, error } = await supabase
      .from("trip_states")
      .select("*")
      .eq("user_id", user_id)
      .maybeSingle();

    if (!error && data) {
      return data;
    }
  } catch (err) {
    console.log("Supabase getLongMemory exception:", err.message);
  }
  return {};
}

module.exports = {
  saveMessage,
  getShortMemory,
  getLongMemory
};