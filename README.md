# Smart Parking Sensor System with Distance-Based Warning

An embedded systems final project implementing a car parking distance indicator using **AVR Assembly** on Arduino Uno. The system uses an HC-SR04 ultrasonic sensor to measure distance and provides real-time feedback through an LCD display, LEDs, and a buzzer.

## Features

- **Distance measurement** using HC-SR04 ultrasonic sensor with 3-reading median filter
- **16x2 LCD I2C display** showing real-time distance and zone status
- **3-zone warning system:**
  - 🟢 **SAFE** (>25 cm) — Green LED, no buzzer
  - 🔵 **CAUTION** (10–25 cm) — Blue LED, slow beep
  - 🔴 **WARNING** (<10 cm) — Red LED, fast beep
- **100% AVR Assembly** — no Arduino C/C++ libraries used

## Hardware Components

| Component | Quantity | Description |
|-----------|----------|-------------|
| Arduino Uno (ATmega328P) | 1 | Microcontroller |
| HC-SR04 | 1 | Ultrasonic distance sensor |
| LCD 16x2 I2C (PCF8574) | 1 | Display module |
| LED (Green, Blue, Red) | 3 | Zone indicators |
| Buzzer | 1 | Audio warning |
| Resistor 220Ω | 3 | LED current limiting |

## Pin Mapping

| Pin | Function |
|-----|----------|
| D2 (PD2) | LED Green (SAFE) |
| D3 (PD3) | LED Blue (CAUTION) |
| D4 (PD4) | LED Red (WARNING) |
| D5 (PD5) | Buzzer |
| D8 (PB0) | HC-SR04 TRIG |
| D9 (PB1) | HC-SR04 ECHO |
| A4 (PC4) | I2C SDA |
| A5 (PC5) | I2C SCL |

## Circuit Diagram

```
                    Arduino Uno
                 ┌──────────────────┐
                 │                  │
   HC-SR04       │  D8 ──── TRIG   │
                 │  D9 ──── ECHO   │
                 │                  │
   LEDs          │  D2 ──220Ω── 🟢 │
                 │  D3 ──220Ω── 🔵 │
                 │  D4 ──220Ω── 🔴 │
                 │                  │
   Buzzer        │  D5 ──── BUZ+   │
                 │                  │
   LCD I2C       │  A4 ──── SDA    │
                 │  A5 ──── SCL    │
                 │  5V ──── VCC    │
                 │  GND ─── GND    │
                 └──────────────────┘
```

## Project Structure

```
SmartParkingSensor/
├── SmartParkingSensor/
│   ├── SmartParkingSensor.ino    # Arduino IDE wrapper (empty)
│   └── SmartParkingSensor.S      # Main AVR Assembly source
├── schematic/                    # Circuit schematic files
└── README.md
```

## Technical Details

- **I2C LCD Protocol:** PCF8574 backpack at address `0x27` (4-bit nibble mode)
- **Sensor Filtering:** 3-reading median filter for noise rejection
- **Timer Usage:** Timer1 with prescaler /8 for echo pulse measurement
- **I2C Speed:** ~308 kHz (TWBR=12)

## Group 8
