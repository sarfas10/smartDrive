import fetch from "node-fetch";
import * as functions from "firebase-functions";

const DISTANCE_API_KEY = process.env.DISTANCE_API_KEY;

export const distanceMatrix = functions.https.onCall(async (data, context) => {
  try {
    const origin = data?.origin;
    const destination = data?.destination;

    if (!origin || !destination) {
      throw new functions.https.HttpsError("invalid-argument", "origin and destination required");
    }
    if (!DISTANCE_API_KEY) {
      throw new functions.https.HttpsError("failed-precondition", "API key missing on server");
    }

    const now = Math.floor(Date.now() / 1000);

    const url = new URL("https://maps.googleapis.com/maps/api/distancematrix/json");
    url.searchParams.set("origins", origin);
    url.searchParams.set("destinations", destination);
    url.searchParams.set("units", "metric");
    url.searchParams.set("mode", "driving");
    url.searchParams.set("departure_time", String(now));
    url.searchParams.set("traffic_model", "best_guess");
    url.searchParams.set("key", DISTANCE_API_KEY);

    const r = await fetch(url.toString());
    const j = await r.json();

    const element = j?.rows?.[0]?.elements?.[0];
    if (j.status !== "OK" || !element || element.status !== "OK") {
      return { status: element?.status ?? "ERROR", distanceMeters: null, durationText: null };
    }

    return {
      status: "OK",
      distanceMeters: element.distance.value,
      distanceText: element.distance.text,
      durationText: (element.duration_in_traffic || element.duration).text,
    };
  } catch (err) {
    throw new functions.https.HttpsError("internal", "Server error", String(err));
  }
});
