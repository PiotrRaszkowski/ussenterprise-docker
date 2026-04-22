#!/bin/bash
# ─────────────────────────────────────────────
# LedFX + Shairport-Sync Setup Script
# ─────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "🎵 LedFX + AirPlay Setup"
echo "========================"
echo ""

# 1. Create PulseAudio shared directory
echo "📁 Creating PulseAudio shared directory..."
mkdir -p ./pulse
sudo chown 1000:1000 ./pulse
echo "   ✅ ./pulse created with UID:GID 1000:1000"
echo ""

# 2. Pull images
echo "📦 Pulling Docker images..."
docker compose pull
echo ""

# 3. Start stack
echo "🚀 Starting LedFX stack..."
docker compose up -d
echo ""

# 4. Show status
echo "📊 Container status:"
docker compose ps
echo ""

echo "════════════════════════════════════════════"
echo "  ✅ Setup complete!"
echo ""
echo "  LedFX UI:  http://$(hostname -I | awk '{print $1}'):8888"
echo "  AirPlay:   Look for 'LedFX' on your iPhone/Mac"
echo ""
echo "  Next steps:"
echo "  1. Open LedFX UI in your browser"
echo "  2. WLED devices should auto-discover (mDNS)"
echo "  3. If not, click 'Scan for WLED devices'"
echo "  4. Select an effect on a device"
echo "  5. Play music via AirPlay to 'LedFX'"
echo "  6. Enjoy! 🎆🔥"
echo "════════════════════════════════════════════"
