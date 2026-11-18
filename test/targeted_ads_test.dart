import 'package:flutter_test/flutter_test.dart';
import 'package:routine_app/countries.dart';
import 'package:routine_app/main.dart';

void main() {
  group('Targeted Ads Category Tree Matching Tests', () {
    test('Global "all" target matches any user profile', () {
      final bdStudent = {
        'country': 'Bangladesh',
        'status': 'Student',
        'education': 'HSC',
        'goal': 'Study Routine',
      };
      final emptyProfile = <String, dynamic>{};

      expect(AdvertisementTargetMatcher.matchesTarget('all', bdStudent), isTrue);
      expect(AdvertisementTargetMatcher.matchesTarget('all', emptyProfile), isTrue);
      expect(AdvertisementTargetMatcher.matchesTarget('', bdStudent), isTrue);
      expect(AdvertisementTargetMatcher.matchesTarget('root', bdStudent), isTrue);
    });

    test('Country-level targeting matches only users from that country', () {
      final bdProfile = {'country': 'Bangladesh', 'status': 'Employed'};
      final inProfile = {'country': 'India', 'status': 'Employed'};

      expect(AdvertisementTargetMatcher.matchesTarget('BD', bdProfile), isTrue);
      expect(AdvertisementTargetMatcher.matchesTarget('BD', inProfile), isFalse);
      expect(AdvertisementTargetMatcher.matchesTarget('IN', inProfile), isTrue);
      expect(AdvertisementTargetMatcher.matchesTarget('IN', bdProfile), isFalse);
    });

    test('Profession-level targeting matches country and profession', () {
      final bdStudent = {'country': 'Bangladesh', 'status': 'Student'};
      final bdEmployed = {'country': 'Bangladesh', 'status': 'Employed'};

      expect(AdvertisementTargetMatcher.matchesTarget('BD/student', bdStudent), isTrue);
      expect(AdvertisementTargetMatcher.matchesTarget('BD/student', bdEmployed), isFalse);
      expect(AdvertisementTargetMatcher.matchesTarget('BD/employed', bdEmployed), isTrue);
    });

    test('Subcategory-level targeting matches education or goal', () {
      final hscStudent = {
        'country': 'Bangladesh',
        'status': 'Student',
        'education': 'HSC / equivalent',
        'goal': 'exam_prep',
      };
      final bachelorStudent = {
        'country': 'Bangladesh',
        'status': 'Student',
        'education': 'Bachelor',
        'goal': 'exam_prep',
      };

      expect(AdvertisementTargetMatcher.matchesTarget('BD/student/HSC', hscStudent), isTrue);
      expect(AdvertisementTargetMatcher.matchesTarget('BD/student/HSC', bachelorStudent), isFalse);
      expect(AdvertisementTargetMatcher.matchesTarget('BD/student/Bachelor', bachelorStudent), isTrue);
    });

    test('Target priority correctly ranks specificity: subcategory > status > country > all', () {
      final pSubcategory = AdvertisementTargetMatcher.targetPriority('BD/student/HSC');
      final pStatus = AdvertisementTargetMatcher.targetPriority('BD/student');
      final pCountry = AdvertisementTargetMatcher.targetPriority('BD');
      final pGlobal = AdvertisementTargetMatcher.targetPriority('all');

      expect(pSubcategory, greaterThan(pStatus));
      expect(pStatus, greaterThan(pCountry));
      expect(pCountry, greaterThan(pGlobal));
      expect(pGlobal, equals(0));
    });

    test('Worldwide country catalog contains all countries and maps codes properly', () {
      expect(kAllCountries.length, greaterThanOrEqualTo(240));
      expect(kAllCountries.contains('India'), isTrue);
      expect(kAllCountries.contains('Indonesia'), isTrue);
      expect(kAllCountries.contains('Bangladesh'), isTrue);

      expect(isoCountryCode('India'), equals('IN'));
      expect(isoCountryCode('Indonesia'), equals('ID'));
      expect(isoCountryCode('Bangladesh'), equals('BD'));
      expect(isoCountryCode('United States'), equals('US'));

      // Searching 'in' prioritizes India and Indonesia as prefix matches
      const query = 'in';
      final matches = kAllCountries
          .where((c) => c.toLowerCase().contains(query))
          .toList();
      matches.sort((a, b) {
        final aStarts = a.toLowerCase().startsWith(query);
        final bStarts = b.toLowerCase().startsWith(query);
        if (aStarts && !bStarts) return -1;
        if (!aStarts && bStarts) return 1;
        return a.compareTo(b);
      });

      expect(matches.take(2).toList(), containsAll(['India', 'Indonesia']));
    });
  });
}
