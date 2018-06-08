import 'package:gerrit_scraper/gerrit_scraper.dart';

main(List<String> args) {
  // TODO: Switch on args[0] to handle arguments
  print("Generating projects");
  generateProjects().then((dynamic unused) {
    print("Generating lists");
    generateAllLists().then((dynamic unused2) {
      print("Comparing to Android");
      compareToAndroid().then((dynamic unused3) {
        print("Combining the main layers");
        makeCombinedNamesList().then((dynamic unused4) {
          print("Done.");
        });
      });
    });
  });
}
