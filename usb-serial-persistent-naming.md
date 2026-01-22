# USB Serial Device Persistent Naming in Debian/Linux

**Problem:** USB serial devices get dynamic names (`/dev/ttyUSB0`, `/dev/ttyUSB1`) that can change when devices are unplugged/replugged or after reboot.

**Solution:** Use persistent device naming for reliable industrial automation and PVD control systems.

---

## Table of Contents
- [The Problem](#the-problem)
- [Solution 1: by-id Symlinks (Easiest)](#solution-1-by-id-symlinks-easiest)
- [Solution 2: by-path Symlinks (Fixed Installations)](#solution-2-by-path-symlinks-fixed-installations)
- [Solution 3: Custom udev Rules (Best for Production)](#solution-3-custom-udev-rules-best-for-production)
- [Finding Device Attributes](#finding-device-attributes)
- [C# .NET Code Examples](#c-net-code-examples)
- [Production Deployment Strategy](#production-deployment-strategy)
- [Troubleshooting](#troubleshooting)

---

## The Problem

### Dynamic Device Assignment

```bash
# First boot:
STM2 QCM Sensor → /dev/ttyUSB0
PLC Controller  → /dev/ttyUSB1

# After reboot (order changes!):
PLC Controller  → /dev/ttyUSB0
STM2 QCM Sensor → /dev/ttyUSB1

# Your code breaks because it was hardcoded to ttyUSB0
```

### Multiple Device Scenario

```bash
# Plug devices in order 1, 2, 3:
Device 1 → ttyUSB0
Device 2 → ttyUSB1
Device 3 → ttyUSB2

# Unplug device 1, then replug it:
Device 2 → ttyUSB1
Device 3 → ttyUSB2
Device 1 → ttyUSB3  # ❌ Changed!
```

**This breaks hardcoded paths in production code!**

---

## Solution 1: by-id Symlinks (Easiest)

### What It Is
Linux automatically creates persistent symlinks based on USB device vendor, product ID, and serial number.

### Location
```bash
/dev/serial/by-id/
```

### How to Use

```bash
# List available devices:
ls -l /dev/serial/by-id/

# Example output:
# lrwxrwxrwx usb-FTDI_FT232R_USB_UART_A12345-if00-port0 -> ../../ttyUSB0
# lrwxrwxrwx usb-Prolific_USB-Serial_Controller-if00-port0 -> ../../ttyUSB1
# lrwxrwxrwx usb-Inficon_STM2_QCM_SN98765-if00-port0 -> ../../ttyUSB2
```

### In Your Code

**Bad (hardcoded):**
```bash
/dev/ttyUSB0  # ❌ Will break!
```

**Good (persistent):**
```bash
/dev/serial/by-id/usb-Inficon_STM2_QCM_SN98765-if00-port0  # ✅ Always works!
```

### C# Example

```csharp
using System.IO.Ports;

// Persistent device path
string devicePath = "/dev/serial/by-id/usb-Inficon_STM2_QCM_SN98765-if00-port0";

SerialPort port = new SerialPort(devicePath, 9600, Parity.None, 8, StopBits.One);
port.Open();

// Now it always finds the right device!
```

### Pros & Cons

✅ **Pros:**
- No configuration needed (automatic)
- Based on device serial number (unique)
- Survives unplugs/replugs
- Works across reboots

⚠️ **Cons:**
- Path name is long and ugly
- Changes if you replace the physical device (new serial number)
- Each device needs unique serial number (some cheap devices don't have this)

### When to Use
- ✅ Development and testing
- ✅ Multiple identical sensors with unique serial numbers
- ✅ When devices might be unplugged/moved
- ❌ When using cheap USB adapters without serial numbers

---

## Solution 2: by-path Symlinks (Fixed Installations)

### What It Is
Persistent symlinks based on the physical USB port location on the motherboard.

### Location
```bash
/dev/serial/by-path/
```

### How to Use

```bash
# List available devices:
ls -l /dev/serial/by-path/

# Example output:
# lrwxrwxrwx pci-0000:00:14.0-usb-0:1:1.0-port0 -> ../../ttyUSB0
# lrwxrwxrwx pci-0000:00:14.0-usb-0:2:1.0-port0 -> ../../ttyUSB1
```

### Physical Port Mapping

```bash
# Label your USB ports on the PVD controller box:
┌─────────────────────────────┐
│  PVD Controller Box         │
│                             │
│  USB Port 1: STM2 Sensor    │ → /dev/serial/by-path/...usb-0:1:1.0...
│  USB Port 2: PLC Controller │ → /dev/serial/by-path/...usb-0:2:1.0...
│  USB Port 3: Pressure Gauge │ → /dev/serial/by-path/...usb-0:3:1.0...
└─────────────────────────────┘

# Always plug devices into the same physical ports!
```

### In Your Code

```csharp
// Use by-path for fixed USB port locations
string stm2Path = "/dev/serial/by-path/pci-0000:00:14.0-usb-0:1:1.0-port0";

SerialPort stm2Port = new SerialPort(stm2Path, 9600);
stm2Port.Open();
```

### Pros & Cons

✅ **Pros:**
- Stable as long as device stays in same physical USB port
- Can replace broken device, path stays the same
- Good for fixed rack-mounted installations
- Works with devices that don't have serial numbers

⚠️ **Cons:**
- Path changes if you move device to different USB port
- Requires documentation of port assignments
- Path names are long and cryptic

### When to Use
- ✅ Fixed installations (rack-mounted PVD controllers)
- ✅ Devices without unique serial numbers
- ✅ When you control the physical USB port layout
- ❌ Portable setups or when devices need to move

---

## Solution 3: Custom udev Rules (Best for Production)

### What It Is
Create your own meaningful device names using udev rules.

### Result
```bash
# Instead of:
/dev/ttyUSB0
/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_A12345-if00-port0

# You get:
/dev/stm2-sensor
/dev/plc-controller
/dev/pressure-gauge
```

### How to Create udev Rules

#### Step 1: Find Device Attributes

```bash
# Plug in your device and find which ttyUSB it got:
dmesg | grep ttyUSB | tail -1
# Output: FTDI USB Serial Device converter now attached to ttyUSB0

# Get device attributes for udev rule:
udevadm info -a /dev/ttyUSB0 | grep -E 'idVendor|idProduct|serial|KERNELS'

# Example output:
# ATTRS{idVendor}=="0403"      ← USB Vendor ID (FTDI)
# ATTRS{idProduct}=="6001"     ← USB Product ID
# ATTRS{serial}=="A12345XYZ"   ← Device Serial Number
# KERNELS=="1-1"               ← USB Port Path
```

#### Step 2: Create udev Rule File

```bash
# Create custom rules file:
sudo nano /etc/udev/rules.d/99-industrial-sensors.rules
```

#### Step 3: Add Rules

**Method A: Match by Serial Number (Best)**

```bash
# STM2 QCM Sensor - Primary
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", \
  ATTRS{serial}=="A12345XYZ", SYMLINK+="stm2-sensor", MODE="0666", GROUP="dialout"

# STM2 QCM Sensor - Backup unit (different serial)
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", \
  ATTRS{serial}=="B67890ABC", SYMLINK+="stm2-sensor-backup", MODE="0666", GROUP="dialout"

# PLC Controller
SUBSYSTEM=="tty", ATTRS{idVendor}=="067b", ATTRS{idProduct}=="2303", \
  ATTRS{serial}=="PLC001", SYMLINK+="plc-controller", MODE="0666", GROUP="dialout"

# Pressure Gauge
SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", \
  ATTRS{serial}=="PRES001", SYMLINK+="pressure-gauge", MODE="0666", GROUP="dialout"
```

**Method B: Match by USB Port (When no serial number)**

```bash
# USB Port 1 → STM2 Sensor
SUBSYSTEM=="tty", KERNELS=="1-1", SYMLINK+="stm2-sensor", MODE="0666", GROUP="dialout"

# USB Port 2 → PLC Controller
SUBSYSTEM=="tty", KERNELS=="1-2", SYMLINK+="plc-controller", MODE="0666", GROUP="dialout"

# USB Port 3 → Pressure Gauge
SUBSYSTEM=="tty", KERNELS=="1-3", SYMLINK+="pressure-gauge", MODE="0666", GROUP="dialout"
```

**Method C: Match by Vendor/Product (Multiple identical devices)**

```bash
# All FTDI devices get numbered names
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", \
  SYMLINK+="ftdi%n", MODE="0666", GROUP="dialout"

# Results: /dev/ftdi0, /dev/ftdi1, /dev/ftdi2, etc.
```

#### Step 4: Reload udev Rules

```bash
# Reload rules:
sudo udevadm control --reload-rules

# Trigger rules for existing devices:
sudo udevadm trigger

# Verify your new device names:
ls -l /dev/stm2-* /dev/plc-* /dev/pressure-*
```

### Using Custom Names in Code

```csharp
using System.IO.Ports;

// Clean, meaningful device names!
SerialPort stm2 = new SerialPort("/dev/stm2-sensor", 9600);
SerialPort plc = new SerialPort("/dev/plc-controller", 19200);
SerialPort pressure = new SerialPort("/dev/pressure-gauge", 9600);

stm2.Open();
plc.Open();
pressure.Open();

// Read from STM2
string data = stm2.ReadLine();
```

### Advanced: Multiple Devices of Same Type

```bash
# Rule for multiple identical STM2 sensors:
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", \
  ATTRS{serial}=="STM2_001", SYMLINK+="stm2-chamber1", MODE="0666", GROUP="dialout"

SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", \
  ATTRS{serial}=="STM2_002", SYMLINK+="stm2-chamber2", MODE="0666", GROUP="dialout"

SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", \
  ATTRS{serial}=="STM2_003", SYMLINK+="stm2-chamber3", MODE="0666", GROUP="dialout"
```

```csharp
// Control multiple chambers:
SerialPort chamber1 = new SerialPort("/dev/stm2-chamber1", 9600);
SerialPort chamber2 = new SerialPort("/dev/stm2-chamber2", 9600);
SerialPort chamber3 = new SerialPort("/dev/stm2-chamber3", 9600);
```

### Pros & Cons

✅ **Pros:**
- **Custom meaningful names** (`/dev/stm2-sensor`)
- **Most reliable** for production systems
- Can set permissions automatically
- Perfect for fleet deployment (100+ systems)
- Can mix matching methods (serial + port)
- Professional and maintainable

⚠️ **Cons:**
- Requires initial setup (one-time per device type)
- Need to document the rules
- Must distribute rules file to all systems

### When to Use
- ✅ **Production deployments** (100+ PVD systems)
- ✅ When you need **clean, meaningful names**
- ✅ **Fleet management** (deploy same rules everywhere)
- ✅ When mixing different device types
- ✅ **Professional installations**

---

## Finding Device Attributes

### Quick Method

```bash
# Plug in device
# Check dmesg for device name:
dmesg | grep -i "tty" | tail -5

# Get all attributes:
udevadm info -a /dev/ttyUSB0
```

### Detailed Method

```bash
# 1. List all USB devices
lsusb

# Example output:
# Bus 001 Device 005: ID 0403:6001 Future Technology Devices International, Ltd FT232 Serial (UART) IC

# 2. Get detailed info (use Bus and Device numbers from lsusb):
lsusb -v -s 001:005

# 3. Check serial number specifically:
udevadm info --query=all --name=/dev/ttyUSB0 | grep SERIAL

# 4. Test which attributes work:
udevadm test /sys/class/tty/ttyUSB0
```

### Common USB-Serial Chipsets

| Chipset | Vendor ID | Product ID | Driver | Notes |
|---------|-----------|------------|--------|-------|
| FTDI FT232 | 0403 | 6001 | ftdi_sio | Most reliable, has serial# |
| Prolific PL2303 | 067b | 2303 | pl2303 | Common, cheap |
| Silicon Labs CP210x | 10c4 | ea60 | cp210x | Good quality |
| CH340/CH341 | 1a86 | 7523 | ch341 | Very cheap, may lack serial# |
| CDC ACM | various | various | cdc_acm | USB standard, varies |

---

## C# .NET Code Examples

### Basic Serial Communication

```csharp
using System;
using System.IO.Ports;

class STM2Sensor
{
    private SerialPort _port;

    public STM2Sensor(string devicePath)
    {
        // Use persistent device path
        _port = new SerialPort(devicePath, 9600, Parity.None, 8, StopBits.One);
        _port.ReadTimeout = 1000;
        _port.WriteTimeout = 1000;
    }

    public void Connect()
    {
        try
        {
            _port.Open();
            Console.WriteLine($"Connected to {_port.PortName}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Failed to connect: {ex.Message}");
            throw;
        }
    }

    public string ReadThickness()
    {
        _port.WriteLine("READ THICKNESS");
        return _port.ReadLine();
    }

    public void Disconnect()
    {
        if (_port.IsOpen)
        {
            _port.Close();
        }
    }
}

// Usage:
class Program
{
    static void Main()
    {
        // Using custom udev rule name:
        STM2Sensor sensor = new STM2Sensor("/dev/stm2-sensor");

        // Or using by-id path:
        // STM2Sensor sensor = new STM2Sensor("/dev/serial/by-id/usb-Inficon_STM2...");

        sensor.Connect();
        string thickness = sensor.ReadThickness();
        Console.WriteLine($"Thickness: {thickness}");
        sensor.Disconnect();
    }
}
```

### Configuration-Based Device Management

```csharp
using System;
using System.IO.Ports;
using System.Collections.Generic;
using Microsoft.Extensions.Configuration;

class DeviceConfig
{
    public string Name { get; set; }
    public string DevicePath { get; set; }
    public int BaudRate { get; set; }
}

class PVDController
{
    private Dictionary<string, SerialPort> _devices = new();

    public void LoadDevices(IConfiguration config)
    {
        var devices = config.GetSection("SerialDevices").Get<List<DeviceConfig>>();

        foreach (var device in devices)
        {
            SerialPort port = new SerialPort(device.DevicePath, device.BaudRate);
            _devices[device.Name] = port;
            port.Open();
            Console.WriteLine($"Opened {device.Name} at {device.DevicePath}");
        }
    }

    public SerialPort GetDevice(string name)
    {
        return _devices[name];
    }
}

// appsettings.json:
/*
{
  "SerialDevices": [
    {
      "Name": "STM2",
      "DevicePath": "/dev/stm2-sensor",
      "BaudRate": 9600
    },
    {
      "Name": "PLC",
      "DevicePath": "/dev/plc-controller",
      "BaudRate": 19200
    },
    {
      "Name": "Pressure",
      "DevicePath": "/dev/pressure-gauge",
      "BaudRate": 9600
    }
  ]
}
*/
```

### Auto-Discovery Using by-id

```csharp
using System;
using System.IO;
using System.Linq;
using System.IO.Ports;

class DeviceDiscovery
{
    public static string[] FindDevicesByVendor(string vendorName)
    {
        string byIdPath = "/dev/serial/by-id/";

        if (!Directory.Exists(byIdPath))
            return Array.Empty<string>();

        return Directory.GetFiles(byIdPath)
            .Where(f => f.Contains(vendorName, StringComparison.OrdinalIgnoreCase))
            .ToArray();
    }

    public static void Main()
    {
        // Find all Inficon devices:
        var inficonDevices = FindDevicesByVendor("Inficon");

        Console.WriteLine($"Found {inficonDevices.Length} Inficon devices:");
        foreach (var device in inficonDevices)
        {
            Console.WriteLine($"  - {device}");

            // Connect to each one:
            SerialPort port = new SerialPort(device, 9600);
            port.Open();
            // ... do work ...
            port.Close();
        }
    }
}
```

---

## Production Deployment Strategy

### For 100+ PVD Systems

#### 1. Standardize Device Names

Create a naming convention:
```
/dev/stm2-sensor      - QCM sensor
/dev/plc-controller   - PLC interface
/dev/pressure-gauge   - Vacuum gauge
/dev/mass-flow-1      - Mass flow controller 1
/dev/mass-flow-2      - Mass flow controller 2
```

#### 2. Create Master udev Rules File

**File: `/etc/udev/rules.d/99-pvd-devices.rules`**

```bash
# PVD System Standard Device Names
# Deploy this file to all systems

# STM2 QCM Sensor (by serial number)
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", \
  ATTRS{serial}=="*STM2*", SYMLINK+="stm2-sensor", MODE="0666", GROUP="dialout"

# PLC Controller (by vendor/product)
SUBSYSTEM=="tty", ATTRS{idVendor}=="067b", ATTRS{idProduct}=="2303", \
  SYMLINK+="plc-controller", MODE="0666", GROUP="dialout"

# Pressure Gauge (by USB port - always port 3)
SUBSYSTEM=="tty", KERNELS=="1-3", \
  SYMLINK+="pressure-gauge", MODE="0666", GROUP="dialout"

# Mass Flow Controllers (by serial pattern)
SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{serial}=="MFC1*", \
  SYMLINK+="mass-flow-1", MODE="0666", GROUP="dialout"

SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{serial}=="MFC2*", \
  SYMLINK+="mass-flow-2", MODE="0666", GROUP="dialout"
```

#### 3. Deployment Script

Add to your `debian-auto-setup.sh` or create `deploy-pvd-devices.sh`:

```bash
#!/bin/bash
# Deploy PVD device udev rules

echo "Deploying PVD device udev rules..."

# Copy rules file
sudo cp 99-pvd-devices.rules /etc/udev/rules.d/

# Add user to dialout group (for serial access)
sudo usermod -aG dialout $USER

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# Verify devices
echo "Configured devices:"
ls -l /dev/stm2-* /dev/plc-* /dev/pressure-* /dev/mass-flow-* 2>/dev/null

echo "Done! Log out and back in for group changes to take effect."
```

#### 4. Application Configuration

**appsettings.json** (same for all 100 systems):

```json
{
  "PVDDevices": {
    "STM2Sensor": {
      "DevicePath": "/dev/stm2-sensor",
      "BaudRate": 9600,
      "DataBits": 8,
      "Parity": "None",
      "StopBits": "One"
    },
    "PLCController": {
      "DevicePath": "/dev/plc-controller",
      "BaudRate": 19200,
      "DataBits": 8,
      "Parity": "Even",
      "StopBits": "One"
    },
    "PressureGauge": {
      "DevicePath": "/dev/pressure-gauge",
      "BaudRate": 9600,
      "DataBits": 8,
      "Parity": "None",
      "StopBits": "One"
    }
  }
}
```

#### 5. Physical Installation Documentation

Create a standard wiring diagram for all systems:

```
┌─────────────────────────────────────┐
│  PVD Controller - Standard Layout  │
├─────────────────────────────────────┤
│                                     │
│  USB Port 1 (Top):    STM2 Sensor   │  → /dev/stm2-sensor
│  USB Port 2 (Middle): PLC Control   │  → /dev/plc-controller
│  USB Port 3 (Bottom): Pressure      │  → /dev/pressure-gauge
│                                     │
│  USB Hub Ports:                     │
│    Hub Port 1: Mass Flow 1          │  → /dev/mass-flow-1
│    Hub Port 2: Mass Flow 2          │  → /dev/mass-flow-2
│                                     │
└─────────────────────────────────────┘

Label all ports clearly!
```

---

## Troubleshooting

### Device Not Appearing

```bash
# Check if device is detected at all:
dmesg | grep -i usb | tail -20

# Check if driver loaded:
lsmod | grep -E "ftdi|pl2303|cp210x|ch341|cdc_acm"

# Manually load driver if needed:
sudo modprobe ftdi_sio
```

### Permission Denied

```bash
# Check current permissions:
ls -l /dev/ttyUSB0

# Add yourself to dialout group:
sudo usermod -aG dialout $USER

# Log out and back in for group change to take effect

# Verify group membership:
groups
```

### udev Rule Not Working

```bash
# Check rule syntax:
sudo udevadm test /sys/class/tty/ttyUSB0

# Check for typos in rule file:
sudo nano /etc/udev/rules.d/99-industrial-sensors.rules

# Reload rules:
sudo udevadm control --reload-rules
sudo udevadm trigger

# Test with specific device:
udevadm info -a /dev/ttyUSB0 | less
```

### by-id Symlink Missing

```bash
# Some cheap devices don't have serial numbers!
# Check if device has serial:
udevadm info /dev/ttyUSB0 | grep SERIAL

# If no serial, use by-path or udev rules instead
```

### Device Disappeared After Reboot

```bash
# Check if device is physically connected:
lsusb

# Check kernel messages:
dmesg | grep -i tty

# Verify USB port has power:
lsusb -t

# Check if udev rules still exist:
ls -l /etc/udev/rules.d/
```

### Testing Serial Communication

```bash
# Install minicom:
sudo apt install minicom

# Test connection:
minicom -D /dev/stm2-sensor -b 9600

# Or use screen:
screen /dev/stm2-sensor 9600

# Exit screen: Ctrl+A, then K, then Y
```

---

## Quick Reference

### Device Discovery

```bash
# List all USB serial devices:
ls -l /dev/ttyUSB* /dev/ttyACM*

# Show by-id paths:
ls -l /dev/serial/by-id/

# Show by-path paths:
ls -l /dev/serial/by-path/

# Find device attributes:
udevadm info -a /dev/ttyUSB0 | grep -E 'idVendor|idProduct|serial'
```

### udev Quick Commands

```bash
# Reload rules:
sudo udevadm control --reload-rules
sudo udevadm trigger

# Test rule:
sudo udevadm test /sys/class/tty/ttyUSB0

# Monitor udev events:
sudo udevadm monitor
```

### Permissions

```bash
# Add user to serial group:
sudo usermod -aG dialout $USER

# Set device permissions in udev rule:
MODE="0666", GROUP="dialout"
```

---

## Summary: Which Method to Use?

| Scenario | Best Method | Why |
|----------|-------------|-----|
| Quick testing | by-id | Automatic, no setup |
| Fixed installation | by-path | Stable port assignments |
| Development | by-id | Easy discovery |
| **Production (100+ systems)** | **Custom udev rules** | **Professional, maintainable** |
| Devices without serial# | by-path or udev (port) | Only option |
| Multiple identical devices | udev (by serial#) | Custom naming per device |
| Fleet deployment | udev rules | Standardize across all systems |

---

## Further Reading

- Linux udev documentation: `man udev`
- udev rules syntax: `man udev.rules`
- Device attributes: `man udevadm`
- Serial port programming: `man termios`

---

**Document Version:** 1.0
**Last Updated:** December 2025
**Author:** Generated for PVD system deployment
**Target Systems:** Debian 13 with .NET development stack
