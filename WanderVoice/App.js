

import React, { useState, useEffect, useRef } from 'react';
import { StyleSheet, Text, View, TextInput, TouchableOpacity, ScrollView, SafeAreaView, KeyboardAvoidingView, Platform, ActivityIndicator } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import * as Speech from 'expo-speech';
import { Audio } from 'expo-av';
import { LinearGradient } from 'expo-linear-gradient';
import api from './services/api';
import ChatBubble from './components/ChatBubble';
import NovaOrb from './components/NovaOrb';

export default function App() {
  const [messages, setMessages] = useState([]);
  const [inputText, setInputText] = useState('');
  const [isTyping, setIsTyping] = useState(false);
  const [tripState, setTripState] = useState(null);
  const [recording, setRecording] = useState(null);
  const scrollViewRef = useRef();

  const startRecording = async () => {
    try {
      await Audio.requestPermissionsAsync();
      await Audio.setAudioModeAsync({ allowsRecordingIOS: true, playsInSilentModeIOS: true });
      const { recording } = await Audio.Recording.createAsync(Audio.RecordingOptionsPresets.HIGH_QUALITY);
      setRecording(recording);
    } catch (err) {
      console.error('Failed to start recording', err);
    }
  };

  const stopRecording = async () => {
    if (!recording) return;
    setRecording(null);
    try {
      await recording.stopAndUnloadAsync();
      await Audio.setAudioModeAsync({ allowsRecordingIOS: false });
      const uri = recording.getURI();
      
      setIsTyping(true);
      const text = await api.transcribeAudio(uri);
      // Auto-send the transcribed text
      sendMessage(text);
    } catch (e) {
      console.error(e);
      setIsTyping(false);
    }
  };

  const sendMessage = async (textToUse = inputText) => {
    if (!textToUse.trim()) return;

    // Add user message to UI
    const newMsg = { id: Date.now().toString(), role: 'user', text: textToUse };
    setMessages(prev => [...prev, newMsg]);
    setInputText('');
    setIsTyping(true);

    try {
      const data = await api.chat(textToUse);
      setIsTyping(false);

      if (data.success) {
        setTripState(data.trip_state);
        
        // Add AI message
        const aiMsg = { 
          id: (Date.now() + 1).toString(), 
          role: 'assistant', 
          text: data.reply,
          intent: data.intent,
          tool_result: data.tool_result,
          language: data.language
        };
        setMessages(prev => [...prev, aiMsg]);
        
        // Speak the response
        if (data.reply) {
          Speech.speak(data.reply, { language: data.intent?.parameters?.language === 'chinese' ? 'zh-CN' : 'en-US' });
        }
      } else {
        setMessages(prev => [...prev, { id: Date.now().toString(), role: 'assistant', text: "Error: " + data.error }]);
      }
    } catch (error) {
      setIsTyping(false);
      setMessages(prev => [...prev, { id: Date.now().toString(), role: 'assistant', text: "Network error connecting to the Travel AI." }]);
    }
  };

  return (
    <LinearGradient colors={['#dbeafe', '#f0f9ff', '#ffffff']} style={styles.container}>
      <SafeAreaView style={styles.safeArea}>
        <View style={styles.header}>
          <Text style={styles.headerTitle}>Travel AI Assistant</Text>
        </View>

      <ScrollView style={styles.chatArea} contentContainerStyle={{ padding: 16 }}>
        {messages.length === 0 && (
          <View style={styles.emptyState}>
            <Text style={styles.greeting}>Where to next?</Text>
            <Text style={styles.subtitle}>Ask me to plan a trip, check weather, or give recommendations.</Text>
          </View>
        )}
        
        {messages.map(msg => (
          <ChatBubble key={msg.id} message={msg} tripState={tripState} />
        ))}
        
        {isTyping && (
          <View style={styles.typingIndicator}>
            <ActivityIndicator size="small" color="#38bdf8" />
            <Text style={styles.typingText}>Siri is thinking...</Text>
          </View>
        )}
      </ScrollView>

      <KeyboardAvoidingView 
        behavior={Platform.OS === "ios" ? "padding" : "height"}
        style={styles.inputArea}
      >
        <NovaOrb isListening={isTyping} />
        
        <View style={styles.inputRow}>
          <TextInput
            style={styles.input}
            placeholder={recording ? "Listening..." : "Ask anything about your trip..."}
            placeholderTextColor={recording ? "#ef4444" : "#94a3b8"}
            value={inputText}
            onChangeText={setInputText}
            onSubmitEditing={() => sendMessage(inputText)}
            returnKeyType="send"
          />
          {inputText.trim().length > 0 ? (
            <TouchableOpacity style={styles.sendButton} onPress={() => sendMessage(inputText)}>
              <Ionicons name="arrow-up" size={24} color="#fff" />
            </TouchableOpacity>
          ) : (
            <TouchableOpacity 
              style={[styles.sendButton, { backgroundColor: recording ? '#ef4444' : '#3b82f6' }]} 
              onPressIn={startRecording} 
              onPressOut={stopRecording}
            >
              <Ionicons name="mic" size={24} color="#fff" />
            </TouchableOpacity>
          )}
        </View>
      </KeyboardAvoidingView>
      </SafeAreaView>
    </LinearGradient>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  safeArea: {
    flex: 1,
  },
  header: {
    padding: 16,
    borderBottomWidth: 0,
    alignItems: 'center',
  },
  headerTitle: {
    color: '#1e3a8a',
    fontSize: 18,
    fontWeight: '700',
  },
  chatArea: {
    flex: 1,
  },
  emptyState: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 100,
  },
  greeting: {
    color: '#0f172a',
    fontSize: 28,
    fontWeight: 'bold',
    marginBottom: 10,
  },
  subtitle: {
    color: '#475569',
    fontSize: 14,
    textAlign: 'center',
    paddingHorizontal: 20,
    lineHeight: 20,
  },
  inputArea: {
    padding: 16,
    backgroundColor: 'transparent',
  },
  inputRow: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#ffffff',
    borderRadius: 30,
    padding: 4,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.05,
    shadowRadius: 10,
    elevation: 2,
  },
  input: {
    flex: 1,
    color: '#0f172a',
    paddingHorizontal: 16,
    paddingVertical: 12,
    fontSize: 15,
  },
  sendButton: {
    backgroundColor: '#3b82f6',
    width: 40,
    height: 40,
    borderRadius: 20,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 4,
  },
  typingIndicator: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 10,
  },
  typingText: {
    color: '#94a3b8',
    marginLeft: 8,
    fontSize: 14,
  }
});
