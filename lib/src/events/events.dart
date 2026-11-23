/// Vehicle event channel to the Buspilot engine (internal concept,
/// `server.md` › "Vehicle events"). Positions go to Traccar through the
/// Traccar Client SDK, which cannot carry extra data; everything else the
/// phone knows (tags, device health) goes here.
///
/// - [VehicleEvent]: the events and their JSON format.
/// - [JsonlQueue]: the offline queue on the phone.
/// - [EventUploader]: batch upload with retry and backoff.
/// - [tagEventFor], [tagsOnBoardEvent], [HealthEventScheduler]: event sources.
library;

export 'event_sources.dart';
export 'event_uploader.dart';
export 'jsonl_queue.dart';
export 'vehicle_event.dart';
