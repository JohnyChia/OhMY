import axios from 'axios';
import { Platform } from 'react-native';

// Use localhost for Web testing to avoid CORS issues
// Use your local IP for testing on a real phone via Expo Go by creating a .env file with EXPO_PUBLIC_API_URL=http://192.168.x.x:3000
const API_URL = process.env.EXPO_PUBLIC_API_URL || (Platform.OS === 'web' ? 'http://localhost:3000' : 'http://192.168.137.1:3000');

const userId = 'mobile_usr_' + Math.random().toString(36).substring(2, 10);

const api = {
  chat: async (message) => {
    try {
      const response = await axios.post(`${API_URL}/api/chat`, {
        user_id: userId,
        message
      });
      return response.data;
    } catch (error) {
      console.error("API Chat Error:", error.message);
      return { success: false, error: error.message };
    }
  },

  clearSession: async () => {
    try {
      const response = await axios.delete(`${API_URL}/api/chat`, {
        data: { user_id: userId }
      });
      return response.data;
    } catch (error) {
      console.error('Error clearing session:', error);
      throw error;
    }
  },

  transcribeAudio: async (audioUri) => {
    try {
      const formData = new FormData();
      formData.append('audio', {
        uri: audioUri,
        type: 'audio/m4a',
        name: 'recording.m4a',
      });

      const response = await fetch(`${API_URL}/api/transcribe`, {
        method: 'POST',
        body: formData,
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      });

      const data = await response.json();
      if (!data.success) throw new Error(data.error);
      return data.text;
    } catch (error) {
      console.error('Error transcribing audio:', error);
      throw error;
    }
  }
};

export default api;
