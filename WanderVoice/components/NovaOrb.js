import React, { useEffect, useRef } from 'react';
import { View, StyleSheet, Animated, Easing } from 'react-native';

export default function NovaOrb({ isListening }) {
  const scale = useRef(new Animated.Value(1)).current;
  const opacity = useRef(new Animated.Value(0.6)).current;
  const idleAnimation = useRef(null);
  const listeningAnimation = useRef(null);

  useEffect(() => {
    if (isListening) {
      if (idleAnimation.current) idleAnimation.current.stop();
      
      listeningAnimation.current = Animated.loop(
        Animated.parallel([
          Animated.sequence([
            Animated.timing(scale, { toValue: 1.3, duration: 1000, easing: Easing.inOut(Easing.ease), useNativeDriver: false }),
            Animated.timing(scale, { toValue: 1, duration: 1000, easing: Easing.inOut(Easing.ease), useNativeDriver: false })
          ]),
          Animated.sequence([
            Animated.timing(opacity, { toValue: 1, duration: 1000, useNativeDriver: false }),
            Animated.timing(opacity, { toValue: 0.6, duration: 1000, useNativeDriver: false })
          ])
        ])
      );
      listeningAnimation.current.start();
    } else {
      if (listeningAnimation.current) listeningAnimation.current.stop();
      
      Animated.parallel([
        Animated.timing(scale, { toValue: 1, duration: 500, useNativeDriver: false }),
        Animated.timing(opacity, { toValue: 0.3, duration: 500, useNativeDriver: false })
      ]).start();
      
      idleAnimation.current = Animated.loop(
        Animated.sequence([
          Animated.timing(opacity, { toValue: 0.6, duration: 1500, useNativeDriver: false }),
          Animated.timing(opacity, { toValue: 0.3, duration: 1500, useNativeDriver: false })
        ])
      );
      idleAnimation.current.start();
    }
  }, [isListening, scale, opacity]);

  return (
    <View style={styles.container}>
      <Animated.View style={[styles.orbCore, { transform: [{ scale }], opacity }]}>
        <View style={styles.orbGlow1} />
        <View style={styles.orbGlow2} />
      </Animated.View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
    justifyContent: 'center',
    height: 80,
    marginBottom: 10,
  },
  orbCore: {
    width: 60,
    height: 60,
    borderRadius: 30,
    backgroundColor: '#fff',
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#38bdf8',
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.8,
    shadowRadius: 20,
    elevation: 10,
  },
  orbGlow1: {
    position: 'absolute',
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: '#ec4899', 
    opacity: 0.6,
    transform: [{ translateX: -4 }, { translateY: -4 }],
  },
  orbGlow2: {
    position: 'absolute',
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: '#3b82f6', 
    opacity: 0.6,
    transform: [{ translateX: 4 }, { translateY: 4 }],
  }
});
