import 'package:wger/features/account/models/account.dart';
import 'package:wger/features/account/models/user_profile.dart';

const tAccount1 = Account(
  username: 'super root',
  email: 'admin@google.com',
  emailVerified: true,
  isTrustworthy: true,
);

final tUserProfile1 = UserProfile(id: 1, weightUnitStr: 'kg');

/// A profile with a height, as an established user has one
final tUserProfileWithHeight = UserProfile(id: 1, weightUnitStr: 'kg', height: 180);
