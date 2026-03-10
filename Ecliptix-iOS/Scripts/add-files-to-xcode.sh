#!/bin/bash

# Ecliptix iOS - Add Files to Xcode (Manual Guide)
# This script opens Xcode and guides you through adding files

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
XCODEPROJ="$PROJECT_ROOT/Ecliptix-iOS.xcodeproj"

echo -e "${BLUE}🔧 Ecliptix iOS - Add Files to Xcode${NC}"
echo -e "${BLUE}=====================================${NC}\n"

# Check if Xcode project exists
if [ ! -d "$XCODEPROJ" ]; then
    echo -e "${RED}❌ Xcode project not found: $XCODEPROJ${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Found Xcode project${NC}\n"

# Instructions
echo -e "${CYAN}📋 Follow these steps to add files to Xcode:${NC}\n"

echo -e "${YELLOW}Step 1: Add Protos Folder${NC}"
echo -e "   1. Open Finder: ${GREEN}open \"$PROJECT_ROOT/Protos\"${NC}"
echo -e "   2. Drag ${GREEN}Protos${NC} folder into Xcode project navigator"
echo -e "   3. ⚠️  Select ${YELLOW}\"Create folder references\"${NC} (blue folder icon)"
echo -e "   4. Check ${GREEN}\"Ecliptix-iOS\"${NC} target"
echo -e "   5. Click ${GREEN}\"Finish\"${NC}\n"

echo -e "${YELLOW}Step 2: Add Scripts Folder${NC}"
echo -e "   1. Open Finder: ${GREEN}open \"$PROJECT_ROOT/Scripts\"${NC}"
echo -e "   2. Drag ${GREEN}Scripts${NC} folder into Xcode"
echo -e "   3. Select ${YELLOW}\"Create groups\"${NC} (yellow folder icon)"
echo -e "   4. Check ${GREEN}\"Ecliptix-iOS\"${NC} target"
echo -e "   5. Click ${GREEN}\"Finish\"${NC}\n"

echo -e "${YELLOW}Step 3: Add Configuration Files${NC}"
echo -e "   Files to add:"
echo -e "   • Package.swift"
echo -e "   • Podfile"
echo -e "   • Makefile"
echo -e "   • .gitignore\n"
echo -e "   Drag these files from Finder into Xcode project root\n"

echo -e "${YELLOW}Step 4: Add Documentation (Optional)${NC}"
echo -e "   1. Right-click project → New Group"
echo -e "   2. Name it ${GREEN}\"Documentation\"${NC}"
echo -e "   3. Add these files:"
echo -e "      • README.md"
echo -e "      • QUICKSTART.md"
echo -e "      • PROTOS_README.md"
echo -e "      • XCODE_SETUP.md"
echo -e "      • PORTING_CHECKLIST.md"
echo -e "      • MIGRATION_SUMMARY.md\n"

echo -e "${YELLOW}Step 5: Add Proto Generation Build Phase${NC}"
echo -e "   1. Select project → Select target ${GREEN}\"Ecliptix-iOS\"${NC}"
echo -e "   2. Go to ${GREEN}\"Build Phases\"${NC} tab"
echo -e "   3. Click ${GREEN}\"+\"${NC} → ${GREEN}\"New Run Script Phase\"${NC}"
echo -e "   4. Rename to ${GREEN}\"Generate Proto Files\"${NC}"
echo -e "   5. Add this script:\n"

cat << 'SCRIPT'
cd "$PROJECT_DIR"

# Export PATH for Homebrew tools
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Run proto generation
if [ -f "./Scripts/generate-protos.sh" ]; then
    echo "🔧 Generating proto files..."
    ./Scripts/generate-protos.sh
else
    echo "error: generate-protos.sh not found"
    exit 1
fi
SCRIPT

echo -e "\n   6. ${YELLOW}Drag phase ABOVE${NC} ${GREEN}\"Compile Sources\"${NC}\n"

echo -e "${YELLOW}Step 6: Add Generated Folder Reference${NC}"
echo -e "   1. First generate protos: ${GREEN}make generate-protos${NC}"
echo -e "   2. Drag ${GREEN}Generated${NC} folder into Xcode"
echo -e "   3. Select ${YELLOW}\"Create folder references\"${NC}"
echo -e "   4. Uncheck target (not needed in target)\n"

echo -e "${CYAN}🚀 Quick Actions:${NC}\n"
echo -e "   Open project:  ${GREEN}open \"$XCODEPROJ\"${NC}"
echo -e "   Open Protos:   ${GREEN}open \"$PROJECT_ROOT/Protos\"${NC}"
echo -e "   Open Scripts:  ${GREEN}open \"$PROJECT_ROOT/Scripts\"${NC}"
echo -e "   Open Finder:   ${GREEN}open \"$PROJECT_ROOT\"${NC}\n"

# Ask to open Xcode
read -p "$(echo -e ${CYAN}Open Xcode now? [Y/n]: ${NC})" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    echo -e "${GREEN}🚀 Opening Xcode...${NC}"
    open "$XCODEPROJ"

    echo -e "\n${CYAN}Opening Finder windows...${NC}"
    open "$PROJECT_ROOT/Protos"
    open "$PROJECT_ROOT/Scripts"
    open "$PROJECT_ROOT"

    echo -e "\n${GREEN}✅ Xcode and Finder opened!${NC}"
    echo -e "${YELLOW}⚠️  Follow the steps above to add files manually.${NC}"
else
    echo -e "${YELLOW}Skipped opening Xcode.${NC}"
    echo -e "Open manually with: ${GREEN}open \"$XCODEPROJ\"${NC}"
fi

echo -e "\n${BLUE}📚 For detailed instructions, see:${NC}"
echo -e "   ${GREEN}XCODE_SETUP.md${NC}"
echo ""
