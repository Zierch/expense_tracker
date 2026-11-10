/// Names the app itself used to ship, and what they are called now.
///
/// A backup is a file, and a file outlives the release that wrote it. Every
/// snapshot taken between v1.10.0 and v1.11.0 names an income subcategory
/// "Pocket Money"; this build ships "Allowance". An import matches subcategories
/// on the name in the file, so without this table restoring such a backup would
/// quietly create a second income subcategory beside the renamed one, and the
/// month would be split across two names for the same thing — visible as a
/// category list with a duplicate in it and a pie chart with two slices where
/// the user expects one.
///
/// Only names *this app* renamed belong here. A user's own "Pocket Money" is
/// their data, not a stale default, and is left alone: the map is keyed by the
/// transaction type as well, because a name can legitimately exist on both
/// sides, and it only ever rewrites a name the app stopped shipping.
library;

/// Subcategory names the app renamed, keyed by type and then by the old name.
const Map<String, Map<String, String>> _renamed = <String, Map<String, String>>{
  'income': <String, String>{
    // v1.10.0 renamed Allowance to Pocket Money; v1.11.0 renamed it back.
    'Pocket Money': 'Allowance',
  },
};

/// The name [subcategoryName] has in this build, for a row of [type].
///
/// Returns the name unchanged when it was never renamed — which is every name
/// except the handful in [_renamed], including every name the user typed.
String resolveImportedSubcategoryName(String subcategoryName, String type) {
  return _renamed[type]?[subcategoryName] ?? subcategoryName;
}
