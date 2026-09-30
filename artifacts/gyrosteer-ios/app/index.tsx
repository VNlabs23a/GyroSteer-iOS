import AsyncStorage from '@react-native-async-storage/async-storage';
import { Feather } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import { Gyroscope } from 'expo-sensors';
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  AppState,
  Keyboard,
  PanResponder,
  Platform,
  Pressable,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  TextInput,
  View,
  useWindowDimensions,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useColors } from '@/hooks/useColors';

const PREFS_KEY = 'gyrosteer.preferences.v1';
const TAU_DEGREES = 180 / Math.PI;
const DEFAULT_PORT = '8080';

const CONTROL_BUTTONS = [
  { key: 'SHIFT_DOWN', label: 'SHIFT DOWN', short: '−', bit: 0 },
  { key: 'SHIFT_UP', label: 'SHIFT UP', short: '+', bit: 1 },
  { key: 'NITRO', label: 'NITRO', short: 'N', bit: 2 },
  { key: 'HANDBRAKE', label: 'HANDBRAKE', short: 'HB', bit: 3 },
  { key: 'DRS', label: 'DRS', short: 'DRS', bit: 4 },
  { key: 'HORN', label: 'HORN', short: 'H', bit: 5 },
  { key: 'TC_PLUS', label: 'TC +', short: 'TC+', bit: 6 },
  { key: 'TC_MINUS', label: 'TC −', short: 'TC−', bit: 7 },
  { key: 'ABS_PLUS', label: 'ABS +', short: 'ABS+', bit: 8 },
  { key: 'ABS_MINUS', label: 'ABS −', short: 'ABS−', bit: 9 },
  { key: 'PIT', label: 'PIT', short: 'PIT', bit: 10 },
  { key: 'PAUSE', label: 'PAUSE', short: 'Ⅱ', bit: 11 },
] as const;

type ControlKey = (typeof CONTROL_BUTTONS)[number]['key'];
type Preferences = {
  host: string;
  port: string;
  maxAngle: number;
  sensitivity: number;
  deadzone: number;
  linearity: number;
};
type AppColors = ReturnType<typeof useColors>;

const clamp = (value: number, min: number, max: number) =>
  Math.min(max, Math.max(min, value));

function getSteeringOutput(
  angle: number,
  maxAngle: number,
  deadzonePercent: number,
  linearity: number,
) {
  const raw = clamp(angle / (maxAngle / 2), -1, 1);
  const deadzone = clamp(deadzonePercent / 100, 0, 0.5);
  const magnitude = Math.abs(raw);
  if (magnitude <= deadzone) return 0;
  const rescaled = (magnitude - deadzone) / (1 - deadzone);
  return Math.sign(raw) * Math.pow(rescaled, linearity);
}

export default function WheelScreen() {
  const colors = useColors();
  const styles = useMemo(() => makeStyles(colors), [colors.background]);
  const insets = useSafeAreaInsets();
  const { width, height } = useWindowDimensions();
  const isWide = width > height;

  const [host, setHost] = useState('');
  const [port, setPort] = useState(DEFAULT_PORT);
  const [maxAngle, setMaxAngle] = useState(900);
  const [sensitivity, setSensitivity] = useState(4);
  const [deadzone, setDeadzone] = useState(2);
  const [linearity, setLinearity] = useState(1.2);
  const [preferencesReady, setPreferencesReady] = useState(false);
  const [angle, setAngle] = useState(0);
  const [steering, setSteering] = useState(0);
  const [pressedMask, setPressedMask] = useState(0);
  const [pedals, setPedals] = useState({ throttle: false, brake: false });
  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [connectionMessage, setConnectionMessage] = useState('PC not connected');
  const [packetCount, setPacketCount] = useState(0);
  const [moving, setMoving] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [showExtraButtons, setShowExtraButtons] = useState(false);

  const socketRef = useRef<WebSocket | null>(null);
  const sensorSubscriptionRef = useRef<{ remove: () => void } | null>(null);
  const sendTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const connectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const rawAngleRef = useRef(0);
  const zeroOffsetRef = useRef(0);
  const filteredAngleRef = useRef(0);
  const angleRef = useRef(0);
  const steeringRef = useRef(0);
  const maxAngleRef = useRef(maxAngle);
  const sensitivityRef = useRef(sensitivity);
  const deadzoneRef = useRef(deadzone);
  const linearityRef = useRef(linearity);
  const pressedMaskRef = useRef(0);
  const pedalsRef = useRef({ throttle: false, brake: false });
  const lastSampleAtRef = useRef(0);
  const gyroBiasRef = useRef(0);
  const sequenceRef = useRef(0);
  const lockHapticRef = useRef(false);
  const webDragStartAngleRef = useRef(0);
  const movingRef = useRef(false);

  maxAngleRef.current = maxAngle;
  sensitivityRef.current = sensitivity;
  deadzoneRef.current = deadzone;
  linearityRef.current = linearity;
  angleRef.current = angle;
  steeringRef.current = steering;

  useEffect(() => {
    let cancelled = false;
    AsyncStorage.getItem(PREFS_KEY)
      .then((stored) => {
        if (!stored || cancelled) return;
        const parsed = JSON.parse(stored) as Partial<Preferences>;
        if (typeof parsed.host === 'string') setHost(parsed.host);
        if (typeof parsed.port === 'string') setPort(parsed.port);
        if (typeof parsed.maxAngle === 'number')
          setMaxAngle(clamp(parsed.maxAngle, 180, 1080));
        if (typeof parsed.sensitivity === 'number')
          setSensitivity(clamp(parsed.sensitivity, 1, 8));
        if (typeof parsed.deadzone === 'number')
          setDeadzone(clamp(parsed.deadzone, 0, 10));
        if (typeof parsed.linearity === 'number')
          setLinearity(clamp(parsed.linearity, 0.6, 2));
      })
      .catch(() => {
        if (!cancelled) setConnectionMessage('Preferences could not be loaded');
      })
      .finally(() => {
        if (!cancelled) setPreferencesReady(true);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!preferencesReady) return;
    const prefs: Preferences = {
      host,
      port,
      maxAngle,
      sensitivity,
      deadzone,
      linearity,
    };
    AsyncStorage.setItem(PREFS_KEY, JSON.stringify(prefs)).catch(() => {
      setConnectionMessage('Could not save wheel settings');
    });
  }, [host, port, maxAngle, sensitivity, deadzone, linearity, preferencesReady]);

  const applyAngle = useCallback((targetAngle: number) => {
    const limited = clamp(
      targetAngle,
      -(maxAngleRef.current / 2),
      maxAngleRef.current / 2,
    );
    filteredAngleRef.current = limited;
    angleRef.current = limited;
    const nextSteering = getSteeringOutput(
      limited,
      maxAngleRef.current,
      deadzoneRef.current,
      linearityRef.current,
    );
    steeringRef.current = nextSteering;
    setAngle(limited);
    setSteering(nextSteering);
  }, []);

  const stopSession = useCallback((message = 'PC not connected') => {
    if (sendTimerRef.current) clearInterval(sendTimerRef.current);
    if (connectTimerRef.current) clearTimeout(connectTimerRef.current);
    sendTimerRef.current = null;
    connectTimerRef.current = null;
    sensorSubscriptionRef.current?.remove();
    sensorSubscriptionRef.current = null;

    const socket = socketRef.current;
    socketRef.current = null;
    if (socket) {
      socket.onopen = null;
      socket.onmessage = null;
      socket.onerror = null;
      socket.onclose = null;
      try {
        socket.close();
      } catch {
        // The connection may already have closed.
      }
    }

    setConnecting(false);
    setConnected(false);
    setConnectionMessage(message);
    pressedMaskRef.current = 0;
    pedalsRef.current = { throttle: false, brake: false };
    setPressedMask(0);
    setPedals({ throttle: false, brake: false });
    setMoving(false);
    movingRef.current = false;
    lastSampleAtRef.current = 0;
    gyroBiasRef.current = 0;
    lockHapticRef.current = false;
  }, []);

  useEffect(() => {
    const appStateSub = AppState.addEventListener('change', (state) => {
      if (state !== 'active' && socketRef.current) {
        stopSession('Paused while GyroSteer is in the background');
      }
    });
    return () => appStateSub.remove();
  }, [stopSession]);

  useEffect(
    () => () => {
      stopSession();
    },
    [stopSession],
  );

  const setControlButton = (key: ControlKey, isPressed: boolean) => {
    const button = CONTROL_BUTTONS.find((item) => item.key === key);
    if (!button) return;
    const bit = 1 << button.bit;
    const nextMask = isPressed
      ? pressedMaskRef.current | bit
      : pressedMaskRef.current & ~bit;
    pressedMaskRef.current = nextMask;
    setPressedMask(nextMask);
    if (isPressed) {
      Haptics.selectionAsync().catch(() => undefined);
    }
  };

  const setPedal = (pedal: 'throttle' | 'brake', isPressed: boolean) => {
    const next = { ...pedalsRef.current, [pedal]: isPressed };
    pedalsRef.current = next;
    setPedals(next);
    if (isPressed) Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => undefined);
  };

  const connectToPc = async () => {
    if (connected || connecting) {
      stopSession();
      return;
    }

    const cleanHost = host.trim().replace(/^wss?:\/\//i, '').replace(/\/+$/, '');
    const numericPort = Number(port);
    if (!cleanHost) {
      setConnectionMessage('Enter your PC’s local IP address');
      return;
    }
    if (!Number.isInteger(numericPort) || numericPort < 1 || numericPort > 65535) {
      setConnectionMessage('Enter a valid port from 1 to 65535');
      return;
    }

    Keyboard.dismiss();
    const socketHost =
      cleanHost.includes(':') && !cleanHost.startsWith('[')
        ? `[${cleanHost}]`
        : cleanHost;
    setConnecting(true);
    setConnectionMessage(`Connecting to ${cleanHost}:${numericPort}`);

    let socket: WebSocket;
    try {
      socket = new WebSocket(`ws://${socketHost}:${numericPort}`);
    } catch {
      setConnecting(false);
      setConnectionMessage('Could not open a connection. Check the PC address.');
      return;
    }
    socketRef.current = socket;

    connectTimerRef.current = setTimeout(() => {
      if (socketRef.current === socket && socket.readyState !== WebSocket.OPEN) {
        stopSession('Connection timed out — check the PC receiver and Wi-Fi');
      }
    }, 8000);

    socket.onopen = async () => {
      if (socketRef.current !== socket) return;
      if (connectTimerRef.current) clearTimeout(connectTimerRef.current);
      connectTimerRef.current = null;

      let sensorAvailable = false;
      try {
        sensorAvailable = await Gyroscope.isAvailableAsync();
      } catch {
        sensorAvailable = false;
      }
      if (!sensorAvailable) {
        stopSession('This device does not report gyroscope data');
        return;
      }
      if (socketRef.current !== socket) return;

      setConnecting(false);
      setConnected(true);
      setConnectionMessage(`Connected to ${cleanHost}`);
      setPacketCount(0);
      lastSampleAtRef.current = 0;
      gyroBiasRef.current = 0;
      Gyroscope.setUpdateInterval(16);
      sensorSubscriptionRef.current = Gyroscope.addListener(({ z }) => {
        const now = Date.now();
        if (!lastSampleAtRef.current) {
          lastSampleAtRef.current = now;
          return;
        }
        const elapsedSeconds = clamp(
          (now - lastSampleAtRef.current) / 1000,
          0,
          0.08,
        );
        lastSampleAtRef.current = now;

        let angularRate = z - gyroBiasRef.current;
        const isTurning = Math.abs(angularRate) > 0.025;
        if (!isTurning) {
          gyroBiasRef.current += (z - gyroBiasRef.current) * 0.02;
          angularRate = 0;
        }
        setMoving(isTurning);
        movingRef.current = isTurning;

        rawAngleRef.current +=
          angularRate * elapsedSeconds * TAU_DEGREES * sensitivityRef.current;
        const requestedAngle = rawAngleRef.current - zeroOffsetRef.current;
        const target = clamp(
          requestedAngle,
          -(maxAngleRef.current / 2),
          maxAngleRef.current / 2,
        );
        const smoothed =
          filteredAngleRef.current + (target - filteredAngleRef.current) * 0.28;
        applyAngle(smoothed);

        const halfAngle = maxAngleRef.current / 2;
        const nearLock = Math.abs(smoothed) >= halfAngle - 18;
        if (nearLock && !lockHapticRef.current) {
          Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium).catch(() => undefined);
        }
        lockHapticRef.current = nearLock;
      });

      sequenceRef.current = 0;
      sendTimerRef.current = setInterval(() => {
        if (socket.readyState !== WebSocket.OPEN) return;
        sequenceRef.current = (sequenceRef.current + 1) & 0xffff;
        const payload = {
          type: 'wheel',
          seq: sequenceRef.current,
          steering: steeringRef.current,
          axis: steeringRef.current,
          angle: angleRef.current,
          buttons: pressedMaskRef.current,
          accel: pedalsRef.current.throttle ? 1 : 0,
          brake: pedalsRef.current.brake ? 1 : 0,
          isMoving: movingRef.current,
        };
        try {
          socket.send(JSON.stringify(payload));
          if (sequenceRef.current % 10 === 0) {
            setPacketCount((count) => count + 10);
          }
        } catch {
          stopSession('Connection lost — reconnect to continue');
        }
      }, 16);
    };

    socket.onerror = () => {
      if (socketRef.current === socket) {
        stopSession('Connection failed — check the IP, port, and PC firewall');
      }
    };
    socket.onclose = () => {
      if (socketRef.current === socket) {
        stopSession('PC connection closed');
      }
    };
  };

  const recenter = () => {
    zeroOffsetRef.current = rawAngleRef.current;
    applyAngle(0);
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(
      () => undefined,
    );
  };

  const changeMaxAngle = (delta: number) => {
    const next = clamp(maxAngleRef.current + delta, 180, 1080);
    maxAngleRef.current = next;
    setMaxAngle(next);
    applyAngle(angleRef.current);
  };

  const changeSensitivity = (delta: number) => {
    const next = Math.round(clamp(sensitivityRef.current + delta, 1, 8) * 10) / 10;
    sensitivityRef.current = next;
    setSensitivity(next);
  };

  const changeDeadzone = (delta: number) => {
    const next = Math.round(clamp(deadzoneRef.current + delta, 0, 10) * 10) / 10;
    deadzoneRef.current = next;
    setDeadzone(next);
    applyAngle(angleRef.current);
  };

  const changeLinearity = (delta: number) => {
    const next = Math.round(clamp(linearityRef.current + delta, 0.6, 2) * 10) / 10;
    linearityRef.current = next;
    setLinearity(next);
    applyAngle(angleRef.current);
  };

  const wheelPanResponder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => Platform.OS === 'web',
      onMoveShouldSetPanResponder: () => Platform.OS === 'web',
      onPanResponderGrant: (event) => {
        webDragStartAngleRef.current = angleRef.current;
      },
      onPanResponderMove: (_, gestureState) => {
        if (Platform.OS !== 'web') return;
        const virtualSpan = Math.max(width * 0.55, 220);
        const nextAngle =
          webDragStartAngleRef.current +
          (gestureState.dx / virtualSpan) * maxAngleRef.current;
        applyAngle(nextAngle);
      },
    }),
  ).current;

  const statusColor = connected
    ? colors.primary
    : connecting
      ? colors.accent
      : colors.mutedForeground;
  const safeTop =
    Platform.OS === 'web' ? Math.max(insets.top, 67) : insets.top;
  const safeBottom =
    Platform.OS === 'web' ? Math.max(insets.bottom, 34) : insets.bottom;

  return (
    <View
      style={[
        styles.screen,
        { paddingTop: safeTop, paddingBottom: safeBottom },
      ]}
    >
      <StatusBar barStyle="light-content" />
      <ScrollView
        contentContainerStyle={[
          styles.content,
          isWide ? styles.wideContent : undefined,
        ]}
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
      >
        <View style={styles.topBar}>
          <View style={styles.brandRow}>
            <View style={styles.brandMark}>
              <Feather name="disc" size={19} color={colors.primary} />
            </View>
            <View>
              <Text style={styles.brandName}>GYROSTEER</Text>
              <Text style={styles.brandSub}>PHONE WHEEL · PC BRIDGE</Text>
            </View>
          </View>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={showSettings ? 'Hide setup' : 'Show setup'}
            onPress={() => setShowSettings((value) => !value)}
            style={({ pressed }) => [
              styles.iconButton,
              pressed && styles.pressed,
            ]}
            testID="settings-toggle"
          >
            <Feather
              name={showSettings ? 'x' : 'sliders'}
              size={20}
              color={colors.foreground}
            />
          </Pressable>
        </View>

        <View style={styles.connectionCard}>
          <View style={styles.connectionHeading}>
            <View style={styles.connectionLabelGroup}>
              <View
                style={[styles.statusDot, { backgroundColor: statusColor }]}
              />
              <Text style={styles.connectionTitle}>
                {connected ? 'PC LINK ACTIVE' : connecting ? 'CONNECTING' : 'PC LINK'}
              </Text>
            </View>
            <Text style={styles.packetCount}>
              {connected ? `${packetCount.toLocaleString()} packets` : 'WEBSOCKET · WI-FI'}
            </Text>
          </View>
          <View style={styles.connectionInputs}>
            <View style={styles.hostField}>
              <Text style={styles.inputLabel}>PC ADDRESS</Text>
              <TextInput
                accessibilityLabel="PC IP address"
                autoCapitalize="none"
                autoCorrect={false}
                editable={!connected && !connecting}
                keyboardType="numbers-and-punctuation"
                onChangeText={setHost}
                onSubmitEditing={Keyboard.dismiss}
                placeholder="e.g. 192.168.1.50"
                placeholderTextColor={colors.mutedForeground}
                returnKeyType="done"
                style={styles.textInput}
                testID="pc-address-input"
                value={host}
              />
            </View>
            <View style={styles.portField}>
              <Text style={styles.inputLabel}>PORT</Text>
              <TextInput
                accessibilityLabel="PC port"
                editable={!connected && !connecting}
                keyboardType="number-pad"
                maxLength={5}
                onChangeText={setPort}
                onSubmitEditing={Keyboard.dismiss}
                style={styles.textInput}
                testID="pc-port-input"
                value={port}
              />
            </View>
            <Pressable
              accessibilityRole="button"
              onPress={connectToPc}
              style={({ pressed }) => [
                styles.connectButton,
                connected && styles.disconnectButton,
                pressed && styles.pressed,
              ]}
              testID="connect-button"
            >
              {connecting ? (
                <ActivityIndicator
                  size="small"
                  color={connected ? colors.foreground : colors.primaryForeground}
                />
              ) : (
                <Feather
                  name={connected ? 'square' : 'wifi'}
                  size={16}
                  color={connected ? colors.foreground : colors.primaryForeground}
                />
              )}
              <Text
                style={[
                  styles.connectButtonText,
                  connected && styles.disconnectButtonText,
                ]}
              >
                {connected || connecting ? 'STOP' : 'CONNECT'}
              </Text>
            </Pressable>
          </View>
          <Text
            accessibilityLiveRegion="polite"
            style={[styles.connectionMessage, { color: statusColor }]}
            testID="connection-status"
          >
            {connectionMessage}
          </Text>
        </View>

        <View style={[styles.dashboard, isWide && styles.wideDashboard]}>
          <View style={styles.wheelCard}>
            <View style={styles.metricHeader}>
              <Text style={styles.sectionEyebrow}>STEERING INPUT</Text>
              <View style={styles.rangePill}>
                <Text style={styles.rangePillText}>{maxAngle}° TOTAL</Text>
              </View>
            </View>

            <View style={styles.dialStage}>
              <View
                {...(Platform.OS === 'web'
                  ? wheelPanResponder.panHandlers
                  : {})}
                style={styles.dialTouchArea}
                testID="steering-dial"
              >
                <View
                  style={[
                    styles.wheelRim,
                    {
                      transform: [{ rotate: `${angle}deg` }],
                      width: isWide ? 194 : 184,
                      height: isWide ? 194 : 184,
                      borderRadius: isWide ? 97 : 92,
                    },
                  ]}
                >
                  <View style={styles.wheelRedline} />
                  <View style={styles.wheelSpokeHorizontal} />
                  <View style={styles.wheelSpokeVertical} />
                  <View style={styles.wheelCenter}>
                    <Feather name="crosshair" size={23} color={colors.primary} />
                    <Text style={styles.wheelCenterText}>GS</Text>
                  </View>
                </View>
              </View>
            </View>

            <View style={styles.angleReadout}>
              <Text style={styles.angleValue}>
                {angle > 0 ? '+' : ''}
                {angle.toFixed(1)}
                <Text style={styles.angleUnit}>°</Text>
              </Text>
              <View style={styles.axisReadout}>
                <Text style={styles.axisLabel}>AXIS X</Text>
                <Text style={styles.axisValue}>
                  {steering > 0 ? '+' : ''}
                  {steering.toFixed(3)}
                </Text>
              </View>
            </View>

            <View style={styles.lockTrack}>
              <View style={styles.lockCenterMark} />
              <View
                style={[
                  styles.lockPosition,
                  {
                    left: `${50 + clamp(steering, -1, 1) * 46}%`,
                    backgroundColor:
                      Math.abs(steering) > 0.94 ? colors.accent : colors.primary,
                  },
                ]}
              />
            </View>
            <View style={styles.lockLabels}>
              <Text style={styles.lockLabel}>−{maxAngle / 2}°</Text>
              <Text style={styles.lockLabel}>
                {moving ? 'TURNING' : 'CENTERED'}
              </Text>
              <Text style={styles.lockLabel}>+{maxAngle / 2}°</Text>
            </View>
            {Platform.OS === 'web' && (
              <Text style={styles.previewHint}>Drag the wheel to preview steering</Text>
            )}
          </View>

          <View
            style={[
              styles.controlsCard,
              isWide ? styles.wideControlsCard : undefined,
            ]}
          >
            <View style={styles.metricHeader}>
              <Text style={styles.sectionEyebrow}>DRIVING CONTROLS</Text>
              <Pressable
                accessibilityRole="button"
                onPress={recenter}
                style={({ pressed }) => [
                  styles.recenterButton,
                  pressed && styles.pressed,
                ]}
                testID="recenter-button"
              >
                <Feather name="rotate-ccw" size={14} color={colors.primary} />
                <Text style={styles.recenterText}>RECENTER</Text>
              </Pressable>
            </View>

            <View style={styles.paddleRow}>
              <ControlPad
                colors={colors}
                isPressed={Boolean(pressedMask & 1)}
                label="SHIFT DOWN"
                onPressIn={() => setControlButton('SHIFT_DOWN', true)}
                onPressOut={() => setControlButton('SHIFT_DOWN', false)}
                shortLabel="−"
                testID="shift-down"
              />
              <ControlPad
                colors={colors}
                isPressed={Boolean(pressedMask & 2)}
                label="SHIFT UP"
                onPressIn={() => setControlButton('SHIFT_UP', true)}
                onPressOut={() => setControlButton('SHIFT_UP', false)}
                shortLabel="+"
                testID="shift-up"
              />
            </View>

            <View style={styles.pedalRow}>
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Brake pedal"
                onPressIn={() => setPedal('brake', true)}
                onPressOut={() => setPedal('brake', false)}
                style={({ pressed }) => [
                  styles.pedal,
                  styles.brakePedal,
                  pedals.brake && styles.brakePressed,
                  pressed && styles.pedalPressed,
                ]}
                testID="brake-pedal"
              >
                <Feather
                  name="minus"
                  size={16}
                  color={pedals.brake ? colors.foreground : colors.accent}
                />
                <Text style={styles.pedalName}>BRAKE</Text>
                <View style={styles.pedalMeter}>
                  <View
                    style={[
                      styles.pedalMeterFill,
                      styles.brakeMeterFill,
                      { width: pedals.brake ? '100%' : '4%' },
                    ]}
                  />
                </View>
              </Pressable>
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Throttle pedal"
                onPressIn={() => setPedal('throttle', true)}
                onPressOut={() => setPedal('throttle', false)}
                style={({ pressed }) => [
                  styles.pedal,
                  styles.throttlePedal,
                  pedals.throttle && styles.throttlePressed,
                  pressed && styles.pedalPressed,
                ]}
                testID="throttle-pedal"
              >
                <Feather
                  name="chevron-up"
                  size={16}
                  color={pedals.throttle ? colors.primaryForeground : colors.primary}
                />
                <Text
                  style={[
                    styles.pedalName,
                    pedals.throttle && styles.activePedalName,
                  ]}
                >
                  THROTTLE
                </Text>
                <View style={styles.pedalMeter}>
                  <View
                    style={[
                      styles.pedalMeterFill,
                      { width: pedals.throttle ? '100%' : '4%' },
                    ]}
                  />
                </View>
              </Pressable>
            </View>

            <View style={styles.quickButtonRow}>
              <ControlPad
                colors={colors}
                compact
                isPressed={Boolean(pressedMask & (1 << 2))}
                label="NITRO"
                onPressIn={() => setControlButton('NITRO', true)}
                onPressOut={() => setControlButton('NITRO', false)}
                shortLabel="N"
                testID="nitro-button"
              />
              <ControlPad
                colors={colors}
                compact
                isPressed={Boolean(pressedMask & (1 << 3))}
                label="HANDBRAKE"
                onPressIn={() => setControlButton('HANDBRAKE', true)}
                onPressOut={() => setControlButton('HANDBRAKE', false)}
                shortLabel="HB"
                testID="handbrake-button"
              />
            </View>

            <Pressable
              accessibilityRole="button"
              onPress={() => setShowExtraButtons((value) => !value)}
              style={({ pressed }) => [
                styles.moreButtonsToggle,
                pressed && styles.pressed,
              ]}
              testID="more-buttons-toggle"
            >
              <Text style={styles.moreButtonsText}>
                {showExtraButtons ? 'FEWER BUTTONS' : 'MORE BUTTONS'}
              </Text>
              <Feather
                name={showExtraButtons ? 'chevron-up' : 'chevron-down'}
                size={15}
                color={colors.mutedForeground}
              />
            </Pressable>

            {showExtraButtons && (
              <View style={styles.extraButtonsGrid}>
                {CONTROL_BUTTONS.slice(4).map((button) => (
                  <ControlPad
                    key={button.key}
                    colors={colors}
                    compact
                    isPressed={Boolean(pressedMask & (1 << button.bit))}
                    label={button.label}
                    onPressIn={() => setControlButton(button.key, true)}
                    onPressOut={() => setControlButton(button.key, false)}
                    shortLabel={button.short}
                    testID={`button-${button.key.toLowerCase()}`}
                  />
                ))}
              </View>
            )}
          </View>
        </View>

        {showSettings && (
          <View style={styles.settingsCard}>
            <View style={styles.settingsTitleRow}>
              <View>
                <Text style={styles.sectionEyebrow}>WHEEL SETUP</Text>
                <Text style={styles.settingsTitle}>Tune your response</Text>
              </View>
              <View style={styles.settingsIcon}>
                <Feather name="sliders" size={17} color={colors.primary} />
              </View>
            </View>
            <View style={styles.tuningRow}>
              <TuningControl
                colors={colors}
                label="Rotation"
                onStep={changeMaxAngle}
                suffix="°"
                value={`${maxAngle}`}
              />
              <TuningControl
                colors={colors}
                label="Sensitivity"
                onStep={(delta) => changeSensitivity(delta * 0.5)}
                suffix="×"
                value={sensitivity.toFixed(1)}
              />
            </View>
            <View style={styles.tuningRow}>
              <TuningControl
                colors={colors}
                label="Deadzone"
                onStep={(delta) => changeDeadzone(delta * 0.5)}
                suffix="%"
                value={deadzone.toFixed(1)}
              />
              <TuningControl
                colors={colors}
                label="Linearity"
                onStep={(delta) => changeLinearity(delta * 0.1)}
                suffix=""
                value={linearity.toFixed(1)}
              />
            </View>
            <View style={styles.settingsFooter}>
              <Feather name="info" size={14} color={colors.mutedForeground} />
              <Text style={styles.settingsNote}>
                Settings are saved on this iPhone. Sensitivity is the gyro-to-wheel
                multiplier.
              </Text>
            </View>
          </View>
        )}

        <View style={styles.footer}>
          <Feather name="radio" size={13} color={colors.mutedForeground} />
          <Text style={styles.footerText}>
            Keep your iPhone and PC on the same Wi-Fi network
          </Text>
        </View>
      </ScrollView>
    </View>
  );
}

function ControlPad({
  colors,
  compact = false,
  isPressed,
  label,
  onPressIn,
  onPressOut,
  shortLabel,
  testID,
}: {
  colors: AppColors;
  compact?: boolean;
  isPressed: boolean;
  label: string;
  onPressIn: () => void;
  onPressOut: () => void;
  shortLabel: string;
  testID: string;
}) {
  const styles = useMemo(() => makeStyles(colors), [colors.background]);
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      onPressIn={onPressIn}
      onPressOut={onPressOut}
      style={({ pressed }) => [
        styles.controlPad,
        compact && styles.compactControlPad,
        isPressed && styles.controlPadActive,
        pressed && styles.pressed,
      ]}
      testID={testID}
    >
      <Text
        style={[
          styles.controlPadGlyph,
          compact && styles.compactGlyph,
          isPressed && styles.activeGlyph,
        ]}
      >
        {shortLabel}
      </Text>
      <Text
        numberOfLines={1}
        style={[
          styles.controlPadLabel,
          compact && styles.compactLabel,
          isPressed && styles.activeGlyph,
        ]}
      >
        {label}
      </Text>
    </Pressable>
  );
}

function TuningControl({
  colors,
  label,
  onStep,
  suffix,
  value,
}: {
  colors: AppColors;
  label: string;
  onStep: (delta: number) => void;
  suffix: string;
  value: string;
}) {
  const styles = useMemo(() => makeStyles(colors), [colors.background]);
  return (
    <View style={styles.tuningControl}>
      <Text style={styles.tuningLabel}>{label}</Text>
      <View style={styles.stepper}>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={`Decrease ${label}`}
          onPress={() => onStep(-1)}
          style={({ pressed }) => [
            styles.stepButton,
            pressed && styles.pressed,
          ]}
          testID={`decrease-${label.toLowerCase()}`}
        >
          <Feather name="minus" size={15} color={colors.foreground} />
        </Pressable>
        <Text style={styles.stepValue}>
          {value}
          <Text style={styles.stepSuffix}>{suffix}</Text>
        </Text>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={`Increase ${label}`}
          onPress={() => onStep(1)}
          style={({ pressed }) => [
            styles.stepButton,
            pressed && styles.pressed,
          ]}
          testID={`increase-${label.toLowerCase()}`}
        >
          <Feather name="plus" size={15} color={colors.foreground} />
        </Pressable>
      </View>
    </View>
  );
}

function makeStyles(colors: AppColors) {
  return StyleSheet.create({
    screen: {
      flex: 1,
      backgroundColor: colors.background,
    },
    content: {
      width: '100%',
      maxWidth: 900,
      alignSelf: 'center',
      paddingHorizontal: 16,
      paddingTop: 10,
      paddingBottom: 20,
      gap: 12,
    },
    wideContent: {
      paddingHorizontal: 24,
      gap: 14,
    },
    topBar: {
      minHeight: 48,
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
    },
    brandRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 10,
    },
    brandMark: {
      width: 38,
      height: 38,
      alignItems: 'center',
      justifyContent: 'center',
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.border,
      borderRadius: 12,
    },
    brandName: {
      color: colors.foreground,
      fontSize: 17,
      fontWeight: '800',
      letterSpacing: 2,
    },
    brandSub: {
      marginTop: 2,
      color: colors.mutedForeground,
      fontSize: 9,
      fontWeight: '700',
      letterSpacing: 1.3,
    },
    iconButton: {
      width: 40,
      height: 40,
      alignItems: 'center',
      justifyContent: 'center',
      borderRadius: 12,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.card,
    },
    pressed: {
      opacity: 0.72,
      transform: [{ scale: 0.97 }],
    },
    connectionCard: {
      padding: 13,
      borderRadius: colors.radius,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.card,
      gap: 10,
    },
    connectionHeading: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
    },
    connectionLabelGroup: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 8,
    },
    statusDot: {
      width: 7,
      height: 7,
      borderRadius: 4,
    },
    connectionTitle: {
      color: colors.foreground,
      fontSize: 10,
      fontWeight: '800',
      letterSpacing: 1.2,
    },
    packetCount: {
      color: colors.mutedForeground,
      fontSize: 9,
      fontWeight: '700',
      letterSpacing: 0.4,
    },
    connectionInputs: {
      flexDirection: 'row',
      alignItems: 'flex-end',
      gap: 8,
    },
    hostField: {
      flex: 1,
      minWidth: 100,
    },
    portField: {
      width: 68,
    },
    inputLabel: {
      marginBottom: 5,
      color: colors.mutedForeground,
      fontSize: 9,
      fontWeight: '700',
      letterSpacing: 0.8,
    },
    textInput: {
      height: 40,
      paddingHorizontal: 10,
      borderRadius: 10,
      borderWidth: 1,
      borderColor: colors.input,
      backgroundColor: colors.background,
      color: colors.foreground,
      fontSize: 13,
    },
    connectButton: {
      minWidth: 98,
      height: 40,
      paddingHorizontal: 11,
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 7,
      borderRadius: 10,
      backgroundColor: colors.primary,
    },
    disconnectButton: {
      borderWidth: 1,
      borderColor: colors.input,
      backgroundColor: colors.secondary,
    },
    connectButtonText: {
      color: colors.primaryForeground,
      fontSize: 10,
      fontWeight: '900',
      letterSpacing: 0.8,
    },
    disconnectButtonText: {
      color: colors.foreground,
    },
    connectionMessage: {
      minHeight: 14,
      fontSize: 11,
    },
    dashboard: {
      gap: 12,
    },
    wideDashboard: {
      flexDirection: 'row',
      alignItems: 'stretch',
    },
    wheelCard: {
      flex: 1,
      minWidth: 0,
      paddingHorizontal: 15,
      paddingTop: 14,
      paddingBottom: 12,
      borderRadius: colors.radius,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.card,
    },
    metricHeader: {
      minHeight: 26,
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
    },
    sectionEyebrow: {
      color: colors.mutedForeground,
      fontSize: 9,
      fontWeight: '800',
      letterSpacing: 1.4,
    },
    rangePill: {
      paddingHorizontal: 8,
      paddingVertical: 5,
      borderRadius: 10,
      backgroundColor: colors.secondary,
    },
    rangePillText: {
      color: colors.primary,
      fontSize: 9,
      fontWeight: '800',
      letterSpacing: 0.6,
    },
    dialStage: {
      alignItems: 'center',
      justifyContent: 'center',
      paddingVertical: 13,
    },
    dialTouchArea: {
      width: 216,
      height: 216,
      alignItems: 'center',
      justifyContent: 'center',
    },
    wheelRim: {
      alignItems: 'center',
      justifyContent: 'center',
      borderWidth: 10,
      borderColor: colors.wheelRim,
      backgroundColor: colors.wheelFace,
      shadowColor: colors.primary,
      shadowOffset: { width: 0, height: 0 },
      shadowOpacity: 0.12,
      shadowRadius: 13,
    },
    wheelRedline: {
      position: 'absolute',
      top: -9,
      width: 13,
      height: 18,
      borderRadius: 4,
      backgroundColor: colors.accent,
    },
    wheelSpokeHorizontal: {
      position: 'absolute',
      left: 7,
      right: 7,
      top: '50%',
      height: 13,
      marginTop: -6,
      borderRadius: 5,
      backgroundColor: colors.wheelSpoke,
    },
    wheelSpokeVertical: {
      position: 'absolute',
      top: '50%',
      bottom: 8,
      left: '50%',
      width: 13,
      marginLeft: -6,
      borderRadius: 5,
      backgroundColor: colors.wheelSpoke,
    },
    wheelCenter: {
      width: 57,
      height: 57,
      alignItems: 'center',
      justifyContent: 'center',
      borderWidth: 2,
      borderColor: colors.primary,
      borderRadius: 29,
      backgroundColor: colors.wheelHub,
    },
    wheelCenterText: {
      marginTop: 2,
      color: colors.primary,
      fontSize: 8,
      fontWeight: '900',
      letterSpacing: 1,
    },
    angleReadout: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 20,
    },
    angleValue: {
      color: colors.foreground,
      fontSize: 31,
      fontWeight: '700',
      fontVariant: ['tabular-nums'],
      letterSpacing: -1.2,
    },
    angleUnit: {
      color: colors.mutedForeground,
      fontSize: 17,
      fontWeight: '600',
    },
    axisReadout: {
      alignItems: 'flex-start',
      gap: 3,
    },
    axisLabel: {
      color: colors.mutedForeground,
      fontSize: 8,
      fontWeight: '800',
      letterSpacing: 1,
    },
    axisValue: {
      color: colors.primary,
      fontSize: 12,
      fontWeight: '800',
      fontVariant: ['tabular-nums'],
    },
    lockTrack: {
      height: 6,
      marginTop: 14,
      marginHorizontal: 2,
      borderRadius: 4,
      backgroundColor: colors.secondary,
      position: 'relative',
      justifyContent: 'center',
    },
    lockCenterMark: {
      position: 'absolute',
      left: '50%',
      height: 10,
      width: 1,
      backgroundColor: colors.mutedForeground,
    },
    lockPosition: {
      position: 'absolute',
      top: -2,
      width: 10,
      height: 10,
      marginLeft: -5,
      borderRadius: 5,
      borderWidth: 2,
      borderColor: colors.card,
    },
    lockLabels: {
      marginTop: 7,
      flexDirection: 'row',
      justifyContent: 'space-between',
    },
    lockLabel: {
      color: colors.mutedForeground,
      fontSize: 8,
      fontWeight: '700',
      fontVariant: ['tabular-nums'],
    },
    previewHint: {
      marginTop: 6,
      color: colors.mutedForeground,
      textAlign: 'center',
      fontSize: 9,
    },
    controlsCard: {
      flex: 1,
      minWidth: 0,
      padding: 13,
      borderRadius: colors.radius,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.card,
    },
    wideControlsCard: {
      flex: 1,
    },
    recenterButton: {
      minHeight: 30,
      paddingHorizontal: 8,
      flexDirection: 'row',
      alignItems: 'center',
      gap: 5,
      borderRadius: 9,
      backgroundColor: colors.secondary,
    },
    recenterText: {
      color: colors.primary,
      fontSize: 9,
      fontWeight: '800',
      letterSpacing: 0.6,
    },
    paddleRow: {
      marginTop: 10,
      flexDirection: 'row',
      gap: 9,
    },
    controlPad: {
      flex: 1,
      minHeight: 68,
      alignItems: 'center',
      justifyContent: 'center',
      borderWidth: 1,
      borderColor: colors.input,
      borderRadius: 12,
      backgroundColor: colors.secondary,
    },
    compactControlPad: {
      minHeight: 48,
      paddingHorizontal: 4,
      borderRadius: 10,
    },
    controlPadActive: {
      borderColor: colors.primary,
      backgroundColor: colors.primary,
    },
    controlPadGlyph: {
      color: colors.foreground,
      fontSize: 25,
      fontWeight: '700',
    },
    compactGlyph: {
      fontSize: 15,
      fontWeight: '900',
    },
    activeGlyph: {
      color: colors.primaryForeground,
    },
    controlPadLabel: {
      marginTop: 3,
      color: colors.mutedForeground,
      fontSize: 8,
      fontWeight: '800',
      letterSpacing: 0.7,
    },
    compactLabel: {
      marginTop: 2,
      fontSize: 7,
      letterSpacing: 0.25,
    },
    pedalRow: {
      marginTop: 10,
      flexDirection: 'row',
      gap: 9,
    },
    pedal: {
      flex: 1,
      minHeight: 61,
      paddingHorizontal: 10,
      paddingVertical: 7,
      flexDirection: 'row',
      alignItems: 'center',
      gap: 7,
      borderWidth: 1,
      borderColor: colors.input,
      borderRadius: 11,
      backgroundColor: colors.background,
    },
    brakePedal: {
      borderColor: colors.brakeBorder,
    },
    brakePressed: {
      backgroundColor: colors.accent,
      borderColor: colors.accent,
    },
    throttlePedal: {
      borderColor: colors.throttleBorder,
    },
    throttlePressed: {
      backgroundColor: colors.primary,
      borderColor: colors.primary,
    },
    pedalPressed: {
      transform: [{ scale: 0.98 }],
    },
    pedalName: {
      flex: 1,
      color: colors.foreground,
      fontSize: 9,
      fontWeight: '900',
      letterSpacing: 0.7,
    },
    activePedalName: {
      color: colors.primaryForeground,
    },
    pedalMeter: {
      width: 5,
      height: 29,
      overflow: 'hidden',
      borderRadius: 3,
      backgroundColor: colors.secondary,
      justifyContent: 'flex-end',
    },
    pedalMeterFill: {
      width: '4%',
      height: '100%',
      borderRadius: 3,
      backgroundColor: colors.primary,
    },
    brakeMeterFill: {
      backgroundColor: colors.brakeFill,
    },
    quickButtonRow: {
      marginTop: 9,
      flexDirection: 'row',
      gap: 9,
    },
    moreButtonsToggle: {
      marginTop: 7,
      minHeight: 31,
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 6,
    },
    moreButtonsText: {
      color: colors.mutedForeground,
      fontSize: 8,
      fontWeight: '800',
      letterSpacing: 1,
    },
    extraButtonsGrid: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      gap: 7,
    },
    settingsCard: {
      padding: 15,
      borderRadius: colors.radius,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.card,
      gap: 13,
    },
    settingsTitleRow: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
    },
    settingsTitle: {
      marginTop: 4,
      color: colors.foreground,
      fontSize: 16,
      fontWeight: '700',
    },
    settingsIcon: {
      width: 34,
      height: 34,
      alignItems: 'center',
      justifyContent: 'center',
      borderRadius: 10,
      backgroundColor: colors.secondary,
    },
    tuningRow: {
      flexDirection: 'row',
      gap: 9,
    },
    tuningControl: {
      flex: 1,
      minWidth: 0,
      padding: 10,
      borderRadius: 12,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.background,
    },
    tuningLabel: {
      marginBottom: 9,
      color: colors.mutedForeground,
      fontSize: 10,
      fontWeight: '700',
    },
    stepper: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      gap: 4,
    },
    stepButton: {
      width: 31,
      height: 31,
      alignItems: 'center',
      justifyContent: 'center',
      borderRadius: 9,
      backgroundColor: colors.secondary,
    },
    stepValue: {
      color: colors.foreground,
      fontSize: 15,
      fontWeight: '800',
      fontVariant: ['tabular-nums'],
    },
    stepSuffix: {
      color: colors.primary,
      fontSize: 10,
      fontWeight: '800',
    },
    settingsFooter: {
      flexDirection: 'row',
      alignItems: 'flex-start',
      gap: 7,
    },
    settingsNote: {
      flex: 1,
      color: colors.mutedForeground,
      fontSize: 10,
      lineHeight: 15,
    },
    footer: {
      minHeight: 27,
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 7,
    },
    footerText: {
      color: colors.mutedForeground,
      fontSize: 9,
      textAlign: 'center',
    },
  });
}