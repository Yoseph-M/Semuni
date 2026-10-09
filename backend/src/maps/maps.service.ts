import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export interface LatLng {
  latitude: number;
  longitude: number;
}

export interface DirectionResult {
  success: boolean;
  source: 'gebeta' | 'fallback';
  distanceKm: number;
  durationMinutes: number;
  coordinates: [number, number][]; // [longitude, latitude] or [latitude, longitude]
  instruction?: string;
  /** The provider's own payload, passed through to clients unchanged. */
  raw?: unknown;
}

/** A `[longitude, latitude]` pair, the shape every Gebeta response uses. */
type CoordinatePair = [number, number];

function asCoordinatePair(value: unknown): CoordinatePair | null {
  if (
    Array.isArray(value) &&
    value.length >= 2 &&
    typeof value[0] === 'number' &&
    typeof value[1] === 'number'
  ) {
    return [value[0], value[1]];
  }
  if (value && typeof value === 'object') {
    const point = value as Record<string, unknown>;
    const longitude = point.lon ?? point.lng ?? point.longitude;
    const latitude = point.lat ?? point.latitude;
    if (typeof latitude === 'number' && typeof longitude === 'number') {
      return [longitude, latitude];
    }
  }
  return null;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

@Injectable()
export class MapsService {
  private readonly logger = new Logger(MapsService.name);
  private readonly gebetaApiKey?: string;
  private readonly gebetaBaseUrl: string;

  constructor(private readonly config: ConfigService) {
    this.gebetaApiKey = this.config.get<string>('GEBETA_API_KEY');
    this.gebetaBaseUrl =
      this.config.get<string>('GEBETA_BASE_URL') || 'https://mapapi.gebeta.app';
  }

  getMapConfig() {
    return {
      configured: Boolean(this.gebetaApiKey && this.gebetaApiKey.length > 5),
      defaultCenter: {
        latitude: 9.0222,
        longitude: 38.7468,
      },
      defaultZoom: 12.5,
      styleUrl: 'https://tiles.gebeta.app/styles/raster/raster.json',
    };
  }

  /**
   * Proxies route/direction requests to Gebeta Maps API.
   * If Gebeta API is unavailable or fails, returns a safe interpolated fallback
   * path between the origin and destination coordinates.
   */
  async getDirections(
    originStr: string,
    destinationStr: string,
  ): Promise<DirectionResult> {
    const origin = this.parseCoords(originStr);
    const destination = this.parseCoords(destinationStr);

    if (!origin || !destination) {
      throw new Error(
        'Invalid coordinates format. Expected "lat,lon" (e.g. "9.02,38.75")',
      );
    }

    if (this.gebetaApiKey) {
      try {
        const url = `${this.gebetaBaseUrl}/api/route/direction/?origin=${encodeURIComponent(
          originStr,
        )}&destination=${encodeURIComponent(
          destinationStr,
        )}&apiKey=${this.gebetaApiKey}`;

        const response = await fetch(url, {
          method: 'GET',
          headers: {
            Accept: 'application/json',
          },
          signal: AbortSignal.timeout(6000),
        });

        if (response.ok) {
          const data = (await response.json()) as Record<string, unknown>;
          const coords = this.extractCoords(data);
          const distanceKm =
            typeof data.distance === 'number'
              ? data.distance / 1000
              : this.haversineDistance(origin, destination);
          const durationMin =
            typeof data.duration === 'number'
              ? Math.round(data.duration / 60)
              : Math.max(5, Math.round(distanceKm * 3));

          return {
            success: true,
            source: 'gebeta',
            distanceKm: Number(distanceKm.toFixed(2)),
            durationMinutes: durationMin,
            coordinates: coords.length > 0 ? coords : [
              [origin.longitude, origin.latitude],
              [destination.longitude, destination.latitude],
            ],
            instruction:
              typeof data.instruction === 'string'
                ? data.instruction
                : undefined,
            raw: data,
          };
        } else {
          this.logger.warn(
            `Gebeta directions API returned HTTP ${response.status}: ${await response.text().catch(() => '')}`,
          );
        }
      } catch (err: unknown) {
        this.logger.warn(`Gebeta directions API call failed: ${errorMessage(err)}`);
      }
    }

    // Fallback path calculation
    const distanceKm = this.haversineDistance(origin, destination);
    const durationMinutes = Math.max(5, Math.round(distanceKm * 3)); // Average ~20 km/h in Addis Ababa traffic

    // Generate 5 interpolated intermediate coordinates along the route
    const coordinates: [number, number][] = [];
    const steps = 6;
    for (let i = 0; i <= steps; i++) {
      const t = i / steps;
      const lat = origin.latitude + (destination.latitude - origin.latitude) * t;
      const lon = origin.longitude + (destination.longitude - origin.longitude) * t;
      // Slight road-like curve deflection
      const curve = Math.sin(t * Math.PI) * 0.0015;
      coordinates.push([lon + curve, lat + curve]);
    }

    return {
      success: true,
      source: 'fallback',
      distanceKm: Number(distanceKm.toFixed(2)),
      durationMinutes,
      coordinates,
    };
  }

  async geocode(query: string) {
    if (!this.gebetaApiKey || !query?.trim()) {
      return { data: [] };
    }

    try {
      const url = `${this.gebetaBaseUrl}/api/v1/route/geocode?name=${encodeURIComponent(
        query.trim(),
      )}&apiKey=${this.gebetaApiKey}`;

      const response = await fetch(url, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        signal: AbortSignal.timeout(5000),
      });

      if (response.ok) {
        const data = await response.json();
        return { data };
      }
    } catch (err: unknown) {
      this.logger.warn(`Gebeta geocode call failed: ${errorMessage(err)}`);
    }

    return { data: [] };
  }

  private parseCoords(str: string): LatLng | null {
    if (!str) return null;
    const parts = str.split(',').map((p) => parseFloat(p.trim()));
    if (parts.length === 2 && !isNaN(parts[0]) && !isNaN(parts[1])) {
      return { latitude: parts[0], longitude: parts[1] };
    }
    return null;
  }

  /**
   * Normalises the three coordinate shapes Gebeta is known to return.
   * Anything that is not a numeric pair is dropped rather than passed on as a
   * malformed coordinate.
   */
  private extractCoords(data: unknown): CoordinatePair[] {
    if (!data || typeof data !== 'object') return [];
    const record = data as Record<string, unknown>;

    for (const key of ['coordinates', 'path', 'direction'] as const) {
      const raw = record[key];
      if (!Array.isArray(raw)) continue;
      const pairs = raw
        .map(asCoordinatePair)
        .filter((pair): pair is CoordinatePair => pair !== null);
      if (pairs.length > 0) return pairs;
    }
    return [];
  }

  private haversineDistance(p1: LatLng, p2: LatLng): number {
    const R = 6371; // Earth radius in km
    const dLat = ((p2.latitude - p1.latitude) * Math.PI) / 180;
    const dLon = ((p2.longitude - p1.longitude) * Math.PI) / 180;
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos((p1.latitude * Math.PI) / 180) *
        Math.cos((p2.latitude * Math.PI) / 180) *
        Math.sin(dLon / 2) *
        Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }
}
