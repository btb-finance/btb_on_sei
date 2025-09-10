#!/bin/bash

# BTB Finance Testing Script
# Runs comprehensive tests for the BTB Finance smart contract

set -e

echo "🧪 Running BTB Finance tests..."

# Run Move unit tests
echo "📋 Running Move unit tests..."
sui move test

# Build the package
echo "📦 Building Move package..."
sui move build

echo "✅ All tests passed!"