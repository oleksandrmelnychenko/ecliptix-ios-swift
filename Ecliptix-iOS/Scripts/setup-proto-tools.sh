#!/bin/bash

# Ecliptix iOS - Proto Tools Setup Script
# Checks and installs required tools for proto generation and validation

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔧 Ecliptix iOS - Proto Tools Setup${NC}"
echo -e "${BLUE}====================================${NC}\n"

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo -e "${RED}❌ Homebrew is not installed${NC}"
    echo -e "${YELLOW}Install from: https://brew.sh${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Homebrew installed${NC}"

# Check and install protobuf
if ! command -v protoc &> /dev/null; then
    echo -e "${YELLOW}⚠️  protoc not found. Installing...${NC}"
    brew install protobuf
    echo -e "${GREEN}✓ protoc installed${NC}"
else
    PROTOC_VERSION=$(protoc --version | awk '{print $2}')
    echo -e "${GREEN}✓ protoc installed (version $PROTOC_VERSION)${NC}"
fi

# Check and install swift-protobuf
if ! command -v protoc-gen-swift &> /dev/null; then
    echo -e "${YELLOW}⚠️  protoc-gen-swift not found. Installing...${NC}"
    brew install swift-protobuf
    echo -e "${GREEN}✓ swift-protobuf installed${NC}"
else
    echo -e "${GREEN}✓ protoc-gen-swift installed${NC}"
fi

# Check and install grpc-swift
if ! command -v protoc-gen-grpc-swift &> /dev/null; then
    echo -e "${YELLOW}⚠️  protoc-gen-grpc-swift not found. Installing...${NC}"
    brew install grpc-swift
    echo -e "${GREEN}✓ grpc-swift installed${NC}"
else
    echo -e "${GREEN}✓ protoc-gen-grpc-swift installed${NC}"
fi

# Check and install buf
if ! command -v buf &> /dev/null; then
    echo -e "${YELLOW}⚠️  buf not found. Installing...${NC}"
    brew install bufbuild/buf/buf
    echo -e "${GREEN}✓ buf installed${NC}"
else
    BUF_VERSION=$(buf --version 2>/dev/null || true)
    echo -e "${GREEN}✓ buf installed${NC}${BUF_VERSION:+ (version $BUF_VERSION)}"
fi

echo -e "\n${GREEN}🎉 All tools installed successfully!${NC}"
echo -e "${BLUE}You can now run: ./Scripts/generate-protos.sh${NC}"
echo -e "${BLUE}And validate drift with: ./Scripts/validate-proto-contract.py${NC}"
