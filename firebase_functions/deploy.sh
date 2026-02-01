#!/bin/bash

# DuEasy Cloud Functions Deployment Script
# Automates the deployment process with validation

set -e  # Exit on error

echo "🚀 DuEasy Cloud Functions Deployment"
echo "======================================"
echo ""

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found"
    echo "Install with: npm install -g firebase-tools"
    exit 1
fi

echo "✅ Firebase CLI found: $(firebase --version)"
echo ""

# Check if logged in
if ! firebase projects:list &> /dev/null; then
    echo "❌ Not logged in to Firebase"
    echo "Login with: firebase login"
    exit 1
fi

echo "✅ Logged in to Firebase"
echo ""

# Check if OpenAI API key is set
OPENAI_KEY=$(firebase functions:config:get openai.api_key 2>/dev/null | grep -o '"[^"]*"' | tr -d '"' || echo "")

if [ -z "$OPENAI_KEY" ] || [ "$OPENAI_KEY" = "null" ]; then
    echo "⚠️  OpenAI API key not set"
    echo ""
    read -p "Enter your OpenAI API key: " OPENAI_API_KEY

    if [ -z "$OPENAI_API_KEY" ]; then
        echo "❌ API key required"
        exit 1
    fi

    echo "Setting OpenAI API key..."
    firebase functions:config:set openai.api_key="$OPENAI_API_KEY"
    echo "✅ API key set"
else
    echo "✅ OpenAI API key configured"
fi

# Check if model is set
OPENAI_MODEL=$(firebase functions:config:get openai.model 2>/dev/null | grep -o '"[^"]*"' | tr -d '"' || echo "")

if [ -z "$OPENAI_MODEL" ] || [ "$OPENAI_MODEL" = "null" ]; then
    echo "Setting default model (gpt-4o)..."
    firebase functions:config:set openai.model="gpt-4o"
    echo "✅ Model set to gpt-4o"
else
    echo "✅ Model configured: $OPENAI_MODEL"
fi

echo ""
echo "📦 Installing dependencies..."
npm install

echo ""
echo "🔍 Current configuration:"
firebase functions:config:get

echo ""
echo "🚀 Deploying functions to europe-west1..."
echo ""

# Deploy
firebase deploy --only functions --force

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📊 Monitor your functions:"
echo "   firebase functions:log"
echo ""
echo "💰 Check costs:"
echo "   OpenAI: https://platform.openai.com/usage"
echo "   Firebase: https://console.firebase.google.com/project/_/functions/usage"
echo ""
