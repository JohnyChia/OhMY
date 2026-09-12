# Project Context: Travel App
The project is a collaborative Travel Application.
User (Johny) is specifically responsible for the **AI CHATBOT** module. 

## Team Breakdown & Modules:
- **CHAN YI LYNN**: USER MANAGEMENT (Login, Reg, Verified Traveller, Profile, Bookmarks, Travel Summary, Notifications)
- **HEW MIN FEI**: PERSONALISED RECOMMENDER (Preference Profiling, Personalised Destination Recommendation)
- **YAP JIN KAI**: TRAVEL GROUP (Group creation, Group Discovery Feed, Suggestion Board, Voting System, Drag/Drop Itinerary Builder)
- **CHUA ZHUN YU**: WEATHER AND TRAFFIC (Weather Monitoring, Traffic Monitoring, Travel Alerts)
- **JOHNY CHIA JING YAP (User)**: AI CHATBOT
- **BONG TAI WEI**: COMMUNITY DISCOVERY (Travel experience sharing, Community interaction, Discovery and trip integration)

## AI Chatbot Specific Requirements (Johny's Module)
1. **Multilingual Voice Conversation**: 
   - Interact via voice or text. 
   - Support English, Bahasa Malaysia, Mandarin, and Tamil. 
   - Voice-to-text integration. 
   - AI responses will be presented as Text or Voice depending on the input.
2. **Conversational Trip Planning**: 
   - Users describe preferences using natural language instead of filling forms. 
   - Understand vague/conversational requests. 
   - Confirm travel preferences before generating the itinerary.
3. **Intelligent Re-routing Assistant**: 
   - Continuously monitor weather, traffic, and attraction operating hours. 
   - Detect disruptions affecting the itinerary. 
   - Notify users of changes with explanations. 
   - Generate alternative routes minimizing travel time while keeping preferences.

## Operating Guidelines
- When Johny works on the codebase, focus purely on the **AI Chatbot** components (Context, Intents, Agent loops, Re-routing, Text-to-Speech/Speech-to-Text).
- Rely on the native Function Calling / Agent architecture to handle conversational trip planning elegantly.
- Expect integrations with Zhun Yu's weather/traffic module and Min Fei's recommendation module when building tools for the Chatbot.
