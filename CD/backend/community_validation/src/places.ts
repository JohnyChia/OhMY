export async function getPlaceTypes(
  destination: string,
  attraction: string,
  apiKey?: string,
): Promise<string[]> {
  if (!apiKey) return [];
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 3500);
  try {
    const response = await fetch('https://places.googleapis.com/v1/places:searchText', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': 'places.types',
      },
      body: JSON.stringify({ textQuery: `${attraction}, ${destination}`, maxResultCount: 1 }),
      signal: controller.signal,
    });
    if (!response.ok) return [];
    const body = (await response.json()) as { places?: Array<{ types?: string[] }> };
    return body.places?.[0]?.types ?? [];
  } catch {
    return [];
  } finally {
    clearTimeout(timeout);
  }
}
