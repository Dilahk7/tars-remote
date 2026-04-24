import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:media_remote_phone/main.dart';

void main() {
  testWidgets('renders TARS Remote shell', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const TarsRemoteApp());
    await tester.pump();

    expect(find.text('TARS Remote'), findsOneWidget);
    expect(find.text('Laptop connection'), findsOneWidget);
  });
}
