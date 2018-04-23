import 'package:gerrit_scraper/gerrit_scraper.dart';

main(List<String> args) {
  // TODO: Switch on args[0] to handle arguments
  generateNamesList("docs").then((dynamic unused){
    print("Done");
  });
}
