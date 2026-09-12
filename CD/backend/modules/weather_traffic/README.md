# Weather and Traffic backend module

This module contains Google Weather lookup and traffic-aware Google Routes
processing. The shared Express gateway in `backend/server.js` exposes the
weather and route endpoints.

- `weather-service.js` provides current conditions and hourly forecasts.
- `routing-service.js` requests route alternatives and derives traffic labels
  from traffic-aware travel durations.

The live road traffic layer itself is rendered by Google Maps in Flutter and
does not require a separate backend file.
