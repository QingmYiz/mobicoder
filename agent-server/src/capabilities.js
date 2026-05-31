/**
 * GET /api/capabilities
 * Returns available phone capabilities and their status.
 */
export function getCapabilities() {
  return {
    available: true,
    capabilities: [
      {
        name: 'camera',
        commands: ['camera.snap', 'camera.clip', 'camera.list'],
        description: 'Camera capture - take photos and record video',
      },
      {
        name: 'flash',
        commands: ['flash.on', 'flash.off', 'flash.toggle', 'flash.status'],
        description: 'Flashlight / torch control',
      },
      {
        name: 'location',
        commands: ['location.get'],
        description: 'GPS location',
      },
      {
        name: 'screen',
        commands: ['screen.record'],
        description: 'Screen recording',
      },
      {
        name: 'sensor',
        commands: ['sensor.read', 'sensor.list'],
        description: 'Device sensors (accelerometer, gyroscope, etc.)',
      },
      {
        name: 'haptic',
        commands: ['haptic.vibrate'],
        description: 'Haptic vibration feedback',
      },
      {
        name: 'canvas',
        commands: ['canvas.navigate', 'canvas.eval', 'canvas.snapshot'],
        description: 'WebView canvas control',
      },
      {
        name: 'serial',
        commands: ['serial.list', 'serial.connect', 'serial.disconnect', 'serial.write', 'serial.read'],
        description: 'Serial port communication (USB/BLE)',
      },
      {
        name: 'battery',
        commands: ['battery.status'],
        description: 'Battery status',
      },
    ],
    totalCommands: 20,
  };
}
