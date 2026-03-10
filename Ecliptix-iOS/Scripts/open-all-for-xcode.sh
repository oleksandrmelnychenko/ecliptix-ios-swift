#!/bin/bash

# Автоматично відкриває Xcode, Finder та інструкції
# для швидкого додавання файлів

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear

echo -e "${CYAN}🚀 Відкриваю все для додавання файлів до Xcode...${NC}\n"

# 1. Відкрити інструкцію
echo -e "${GREEN}✓ Відкриваю інструкцію...${NC}"
open "$PROJECT_ROOT/QUICK_ADD_FILES.md"
sleep 1

# 2. Відкрити Xcode
echo -e "${GREEN}✓ Відкриваю Xcode...${NC}"
open "$PROJECT_ROOT/Ecliptix-iOS.xcodeproj"
sleep 2

# 3. Відкрити Finder з папками
echo -e "${GREEN}✓ Відкриваю Finder...${NC}"
open "$PROJECT_ROOT"

echo -e "\n${CYAN}📋 ЩО РОБИТИ ДАЛІ:${NC}\n"

echo -e "${YELLOW}1. В Xcode Project Navigator (ліворуч):${NC}"
echo -e "   Перетягни ЦІ ПАПКИ з Finder:\n"

echo -e "${GREEN}   📂 Protos${NC} (вибери: Create folder references - СИНЯ іконка)"
echo -e "${GREEN}   📂 Scripts${NC} (вибери: Create groups - ЖОВТА іконка)\n"

echo -e "${YELLOW}2. Перетягни ЦІ ФАЙЛИ:${NC}"
echo -e "${GREEN}   📄 Package.swift${NC}"
echo -e "${GREEN}   📄 Podfile${NC}"
echo -e "${GREEN}   📄 Makefile${NC}\n"

echo -e "${YELLOW}3. Додай Build Phase:${NC}"
echo -e "   Target → Build Phases → + → New Run Script Phase"
echo -e "   Назва: ${GREEN}Generate Proto Files${NC}"
echo -e "   Скрипт (скопіюй):\n"

cat << 'BUILDSCRIPT'
cd "$PROJECT_DIR"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if [ -f "./Scripts/generate-protos.sh" ]; then
    ./Scripts/generate-protos.sh
else
    echo "error: generate-protos.sh not found"; exit 1
fi
BUILDSCRIPT

echo -e "\n${YELLOW}4. Перемісти Build Phase ВИЩЕ Compile Sources${NC}\n"

echo -e "${CYAN}📖 Детальна інструкція відкрита в окремому вікні!${NC}\n"

# Показати що відкрито
echo -e "${GREEN}Відкрито:${NC}"
echo -e "  ✓ QUICK_ADD_FILES.md (інструкція)"
echo -e "  ✓ Xcode project"
echo -e "  ✓ Finder з файлами\n"

echo -e "${CYAN}⏱️  Це займе ~5 хвилин${NC}"
echo ""
