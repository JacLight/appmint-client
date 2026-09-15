/// Customer ↔ admin support chat over the appmint `/chat` Socket.IO gateway.
///
/// The app supplies an [AppmintChatConfig] (endpoint, org, a token callback and
/// who the signed-in customer is); the admin answers from the appmint admin
/// dashboard or appmint_mobile. Nothing here imports an app's theme, storage
/// or auth — every app wires it the same way.
library;

export 'src/config.dart';
export 'src/models.dart';
export 'src/service.dart';
export 'src/controller.dart';
export 'src/theme.dart';
export 'src/widgets/chat_view.dart';
export 'src/widgets/support_chat_screen.dart';
