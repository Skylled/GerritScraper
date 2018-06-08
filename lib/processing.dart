import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'scraper.dart';

Future<Map<String, Map<String, dynamic>>> getChanges(String project) async {
  File cacheFile = new File('cache/${project}_changes.json');
  if (!cacheFile.existsSync()) {
    cacheFile.createSync(recursive: true);
    cacheFile.writeAsStringSync('{}');
  }
  Map cachedChanges = json.decode(cacheFile.readAsStringSync());
  Map<String, Map<String, dynamic>> changes = cachedChanges.cast<String,Map<String, dynamic>>();

  String query = 'project:$project status:merged -roll';
  int start = 0;
  bool noDupesFound = true;
  while (noDupesFound) {
    List<Map<String, dynamic>> scrapedChanges = await scrape('changes/', {'q': query, 'S': start.toString()});
    for (Map<String, dynamic> change in scrapedChanges) {
      if (changes.containsKey(change["id"])) {
        // Just in case something else in the 500 found is new
        noDupesFound = false;
      } else {
        changes[change["id"]] = change;
      }
    }
    if (scrapedChanges.length < 500) {
      break;
    }
    start += 500;
  }
  cacheFile.writeAsStringSync(json.encode(changes));
  return changes;
}

// TODO: updateChanges function
// Takes in an MSD loaded from file
// Processes 500 commits at a time, until a duplicate is found
// When found, stop.

Future<Map<String, int>> getAccountsChanges(String project, {Map<String, Map<String, dynamic>> changes}) async {
  Map<String, int> accountChanges = {};
  if (changes == null) {
    changes = await getChanges(project ?? 'garnet');
  }
  for (Map<String, dynamic> change in changes.values) {
    if (accountChanges.containsKey(change['owner']['_account_id'].toString())) {
      accountChanges[change['owner']['_account_id'].toString()]++;
    } else {
      accountChanges[change['owner']['_account_id'].toString()] = 1;
    }
  }
  return accountChanges;
}

Future<List< Map<String, dynamic>>> getAccountsDetails(String project, {Map<String, int> accountsChanges}) async {
  List<Map<String, dynamic>> accounts = [];
  if (accountsChanges == null) {
    print('No accountChanges, loading...');
    accountsChanges = await getAccountsChanges(project);
  }
  List<Future> futures = [];
  accountsChanges.forEach((String accountID, int changes){
    futures.add(() async {
      accounts.add(await scrapeAccount(accountID));
    }());
  });
  await Future.wait(futures);
  return accounts;
}
