import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart';
import 'caching.dart';
import 'processing.dart';
import 'scraper.dart';

List<String> filter = ["All-Projects", "All-Users", "Commit-Queue", "Public-Projects", "Read-Only"];

Future<void> generateAllLists() async {
  List decJson = json.decode(new File('cache/projects.json').readAsStringSync());
  List<String> projects = decJson.cast<String>();
  List<Future> futures = [];
  for (String project in projects) {
    futures.add(generateNamesList(project));
  }
  await Future.wait(futures);
}

Future<void> generateNamesList(String project, {List<Map<String, dynamic>> accountsDetails, Map<String, int> accountsChanges}) async {
  if (accountsChanges == null) {
    accountsChanges = await getAccountsChanges(project);
  }
  if (accountsDetails == null) {
    accountsDetails = await getAccountsDetails(project, accountsChanges: accountsChanges);
  }
  List<Map<String, dynamic>> organizedAccounts = [];
  for (Map<String, dynamic> account in accountsDetails) {
    Map<String, dynamic> orgAccount = {
      'name': account['name'],
      'id': account['_account_id'].toString(), // ID is returned as int
      'email': account['email'],
      'count': accountsChanges[account['_account_id'].toString()],
    };
    organizedAccounts.add(orgAccount);
  }
  if (organizedAccounts.isEmpty)
    return null;
  organizedAccounts.sort((Map<String, dynamic> ac1, Map<String, dynamic> ac2) {
    return ac1['name'].compareTo(ac2['name']);
  });
  // Dart strings really need Python's `title` convenience method. :(
  String output = 'Developers on the ${project.substring(0, 1).toUpperCase() + project.substring(1)} project, sorted by first name\n';
  for (Map<String, dynamic> account in organizedAccounts) {
    output += '${account['id']} - ${account['name']} - ${account['email']}\n';
  }
  File outFile = new File('out/projects/$project.txt');
  if (!outFile.existsSync()) {
    outFile.createSync(recursive: true);
  }
  new File('out/projects/$project.txt').writeAsStringSync(output);
}

// TODO: Refactor this to just use account cache?
Future<void> makeCombinedNamesList() async {
  List<String> projects = ['zircon', 'garnet', 'peridot', 'topaz'];
  Map<String, Map<String, int>> projectAccountsChanges = {};
  List<Map<String, dynamic>> projectAccountsDetails = [];
  for (String project in projects) {
    projectAccountsChanges[project] = await getAccountsChanges(project);
    projectAccountsDetails.addAll(await getAccountsDetails(project, accountsChanges: projectAccountsChanges[project]));
  }
  Set<Map<String, dynamic>> allAccounts = new Set<Map<String, dynamic>>();
  List<String> usedIDs = [];
  for (Map<String, dynamic> account in projectAccountsDetails) {
    if (usedIDs.contains(account['_account_id'].toString()))
      continue;
    usedIDs.add(account['_account_id'].toString());
    int count = 0;
    for (String project in projects) {
      // Add zero if null
      count += projectAccountsChanges[project][account['_account_id'].toString()] ?? 0;
    }
    Map<String, dynamic> orgAccount = {
      'name': account['name'],
      'id': account['_account_id'].toString(), // ID is returned as int
      'email': account['email'],
      'count': count,
    };
    allAccounts.add(orgAccount);
  }
  List<Map<String, dynamic>> organizedAccounts = new List.from(allAccounts);
  organizedAccounts.sort((Map<String, dynamic> ac1, Map<String, dynamic> ac2) {
    return ac1['name'].compareTo(ac2['name']);
  });
  String output = 'Developers on the Fuchsia project, sorted by first name\n';
  for (Map<String, dynamic> account in organizedAccounts) {
    output += '${account['id']} - ${account['name']} - ${account['email']}\n';
  }
  new File('out/layer-devs.txt').writeAsStringSync(output);
}

Future<void> compareToAndroid() async {
  // https://fuchsia-review.googlesource.com/accounts/?suggest&q=armansito@google.com&n=10
  if (!cacheLoaded)
    loadAccountCache();
  List<Future> futures = [];
  List<String> androidDevIDs = [];
  cachedAccounts.forEach((String accountID, Map<String, dynamic> accountData) {
    futures.add(() async {
      if (await scrapeAndroidChanges(accountData["email"]))
        androidDevIDs.add(accountID);
    }());
  });
  await Future.wait(futures);
  List<Map<String, dynamic>> organizedAccounts = [];
  for (String accountID in androidDevIDs) {
    Map<String, dynamic> accountDetails = cachedAccounts[accountID];
    Map<String, dynamic> orgAccount = {
      'name': accountDetails['name'],
      'id': accountID,
      'email': accountDetails['email'],
    };
    organizedAccounts.add(orgAccount);
  }
  organizedAccounts.sort((Map<String, dynamic> ac1, Map<String, dynamic> ac2) {
    return ac1['name'].compareTo(ac2['name']);
  });
  String output = 'Developers who have worked on both Android and Fuchsia\n';
  for (Map<String, dynamic> account in organizedAccounts) {
    output += '${account['id']} - ${account['name']} - ${account['email']}\n';
  }
  new File('out/android-fuchsia.txt').writeAsStringSync(output);
}

Future<dynamic> generateProjects() async {
  // https://fuchsia-review.googlesource.com/projects/
  // headers: {'Cookie': makeCookie()}
  Response res = await get('https://fuchsia-review.googlesource.com/projects/', headers: {'Cookie': makeCookie()});
  if (res.statusCode == HttpStatus.OK) {
    List<String> projectsCache = [];
    Map decJson = json.decode(res.body.substring(5));
    Map<String, Map<String, dynamic>> projects = decJson.cast<String, Map<String, dynamic>>();
    String output = "Fuchsia Projects List\n";
    projects.forEach((String name, Map<String, dynamic> data){
      if (filter.contains(name))
        return;
      output += "$name - ${data['state']}\n";
      projectsCache.add(name);
    });
    new File('out/projects.txt').writeAsStringSync(output);
    new File('cache/projects.json').writeAsStringSync(json.encode(projectsCache));
  } else {
    throw new HttpException('Status code: ${res.statusCode}');
  }
}
