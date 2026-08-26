import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';

export default function ChatBubble({ message, tripState }) {
  const isUser = message.role === 'user';
  
  return (
    <View style={[styles.container, isUser ? styles.userContainer : styles.aiContainer]}>
      {!isUser && (
        <View style={styles.avatar}>
          <Ionicons name="sparkles" size={16} color="#fff" />
        </View>
      )}
      
      <View style={[styles.bubble, isUser ? styles.userBubble : styles.aiBubble]}>
        <Text style={styles.text}>{message.text}</Text>
        
        {message.language && (
          <View style={styles.languageBadge}>
            <Text style={styles.languageText}>{message.language.toUpperCase()}</Text>
          </View>
        )}
        
        {/* Render simple itinerary cards if available */}
        {!isUser && message.tool_result?.days && (
          <View style={styles.card}>
            <View style={styles.cardHeader}>
              <Ionicons name="calendar-outline" size={16} color="#e2e8f0" />
              <Text style={styles.cardTitle}>Travel Itinerary</Text>
            </View>
            {message.tool_result.days.map((d, i) => (
              <View key={i} style={styles.dayRow}>
                <Text style={styles.dayText}>Day {d.day}: {d.title}</Text>
                <Text style={styles.locationText}>{d.location}</Text>
              </View>
            ))}
          </View>
        )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    marginBottom: 16,
    maxWidth: '85%',
  },
  userContainer: {
    alignSelf: 'flex-end',
  },
  aiContainer: {
    alignSelf: 'flex-start',
  },
  avatar: {
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: '#3b82f6',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 8,
    marginTop: 4,
  },
  bubble: {
    padding: 14,
    borderRadius: 20,
  },
  userBubble: {
    backgroundColor: '#3b82f6',
    borderBottomRightRadius: 4,
  },
  aiBubble: {
    backgroundColor: 'rgba(255,255,255,0.1)',
    borderBottomLeftRadius: 4,
  },
  text: {
    color: '#f8fafc',
    fontSize: 16,
    lineHeight: 24,
  },
  card: {
    marginTop: 12,
    backgroundColor: 'rgba(0,0,0,0.2)',
    borderRadius: 12,
    padding: 12,
  },
  cardHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
    paddingBottom: 8,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.1)',
  },
  cardTitle: {
    color: '#e2e8f0',
    fontWeight: 'bold',
    marginLeft: 6,
  },
  dayRow: {
    marginBottom: 8,
  },
  dayText: {
    color: '#f8fafc',
    fontWeight: '600',
    fontSize: 14,
  },
  locationText: {
    color: '#94a3b8',
    fontSize: 12,
    marginTop: 2,
  },
  languageBadge: {
    alignSelf: 'flex-start',
    backgroundColor: 'rgba(255,255,255,0.2)',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 12,
    marginTop: 8,
  },
  languageText: {
    color: '#e2e8f0',
    fontSize: 10,
    fontWeight: 'bold',
  }
});
