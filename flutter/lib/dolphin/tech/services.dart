import 'actions.dart';
import 'api.dart';
import 'cache.dart';
import 'notifications.dart';
import 'repository.dart';
import 'secret_box.dart';
import 'session_store.dart';
import 'state.dart';

/// Plan 19: the technician app's data layer wired together once, for the screens to share. The app builds it with
/// [TechServices.open] and its own launcher (launcher.dart RustdeskSessionLauncher), tests with fakes.
class TechServices {
  final ApiClient api;
  final SessionStore session;
  final OfflineCache cache;
  final TechRepository repo;
  final ConnectionController connection;
  final NotificationPoller poller;
  final TechActions actions;
  final Prefs prefs;

  TechServices._(this.api, this.session, this.cache, this.repo, this.connection, this.poller, this.actions, this.prefs);

  factory TechServices({
    required ApiClient api,
    required SecretBox sessionBox,
    required SecretBox offlineBox,
    required SessionLauncher launcher,
    required Prefs prefs,
    DemoStarter? demoStarter,
  }) {
    final cache = OfflineCache(offlineBox);
    final session = SessionStore(api, sessionBox, cache: cache);
    final repo = TechRepository(api, cache);
    final actions = TechActions(api, launcher, demoStarter: demoStarter, onIdRegistered: session.updateRustdeskId);
    return TechServices._(api, session, cache, repo, ConnectionController(), NotificationPoller(api), actions, prefs);
  }

  /// Production: DPAPI-sealed files in the user's app-support folder, the portal from DolphinBrand.portalUrl.
  static Future<TechServices> open(
          {required SessionLauncher launcher, required Prefs prefs, DemoStarter? demoStarter, ApiClient? api}) async =>
      TechServices(
        api: api ?? ApiClient(),
        sessionBox: await openBox(kSessionBoxName),
        offlineBox: await openBox(kOfflineBoxName),
        launcher: launcher,
        prefs: prefs,
        demoStarter: demoStarter,
      );

  DashboardController dashboard() => DashboardController(repo, connection, prefs, actions: actions);
  PcCardController card(String deviceId) => PcCardController(repo, actions, connection, deviceId);
  RequestsController requests() => RequestsController(repo, connection);
  NotificationsController notifications() => NotificationsController(poller);
  ConfigController config() => ConfigController(repo, connection);

  /// After a sign-in (or a start with a stored one): register this app's ID if needed, start polling. Returns the
  /// portal's refusal of the ID in Persian, or null.
  Future<String?> afterSignIn() async {
    final staff = session.staff;
    if (staff == null) return null;
    poller.start();
    return actions.ensureMyId(staff);
  }

  /// «خروج»: the portal session ends, the token and offline list go, polling stops, memory is cleared.
  Future<void> signOut() async {
    poller.reset();
    repo.reset();
    await session.signOut();
  }

  void dispose() {
    poller.dispose();
    session.dispose();
    connection.dispose();
    api.close();
  }
}
