import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart';

bool _debugging = false;

// Reference guide: https://flutter.io/networking/#example-decoding-json-from-https-get

// Future: Generate XSRF_TOKEN legitimately.

String makeCookie(){
  // TODO: Double-check cookies functionality.
  Map<String, dynamic> cookies = json.decode(new File('cookies.json').readAsStringSync());
  String cookie = '';
  cookies.forEach((String key, dynamic value) {
    cookie += '$key=$value; ';
  });
  // Strip the trailing semicolon and space.
  if (cookie.length > 0)
    return cookie.substring(0, cookie.length - 3);
  return null;
}

// Future: de-dup code from these.
Future<Map<String, dynamic>> scrapeAccount(String accountID) async {
  // print('Scraping for account: $accountID');
  Response res = await get('https://fuchsia-review.googlesource.com/accounts/$accountID', headers: {'Cookie': makeCookie()});
  if (res.statusCode == HttpStatus.OK) {
    Map decJson = json.decode(res.body.substring(5));
    return decJson.cast<String, dynamic>();
  } else {
    throw new HttpException('Status code: ${res.statusCode}');
  }
}

Future<List<Map<String, dynamic>>> scrape(String endpoint, Map<String, dynamic> params) async {
  Uri url = new Uri(
    scheme: 'https',
    host: 'fuchsia-review.googlesource.com',
    path: endpoint,
    queryParameters: params,
  );
  print('Scraping: ${url.toString()}');
  Response res = await get(url);
  if (res.statusCode == HttpStatus.OK) {
    List decJson = json.decode(res.body.substring(5));
    return decJson.cast<Map<String, dynamic>>();
  } else {
    throw new HttpException('Status code: ${res.statusCode}');
  }
}

Future<List<Map<String, dynamic>>> getChanges(String project) async {
  String query = 'project:$project status:merged -roll';
  int start = 0;
  List<Map<String, dynamic>> entries = [];
  while (true) {
    List<Map<String, dynamic>> newEntries = await scrape('changes/', {'q': query, 'S': start.toString()});
    entries.addAll(newEntries);
    if (newEntries.length < 500) {
      break;
    }
    start += 500;
  }
  if (_debugging) {
    new File('logs/${project}_changes_${DateTime.now().toIso8601String()}.json').writeAsStringSync(json.encode(entries));
  }
  return entries;
}

// TODO: updateChanges function
// Takes in an MSD loaded from file
// Processes 500 commits at a time, until a duplicate is found
// When found, stop.

Future<Map<String, int>> getAccountsChanges(String project, {List<Map<String, dynamic>> changes}) async {
  Map<String, int> accountChanges = {};
  if (changes == null) {
    changes = await getChanges(project ?? 'garnet');
  }
  for (Map<String, dynamic> change in changes) {
    if (accountChanges.containsKey(change['owner']['_account_id'].toString())) {
      accountChanges[change['owner']['_account_id'].toString()]++;
    } else {
      accountChanges[change['owner']['_account_id'].toString()] = 1;
    }
  }
  if (_debugging) {
    new File('logs/${project ?? 'unknown'}_account_changes_${DateTime.now().toIso8601String()}.json').writeAsStringSync(json.encode(accountChanges));
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
  if (_debugging) {
    new File('logs/${project ?? 'unknown'}_account_details_${DateTime.now().toIso8601String()}.json').writeAsStringSync(json.encode(accounts));
  }
  return accounts;
}

Future<void> generateNamesList(String project, {List<Map<String, dynamic>> accountsDetails, Map<String, int> accountsChanges}) async {
  if (accountsChanges == null) {
    print('No changes, loading...');
    accountsChanges = await getAccountsChanges(project);
  }
  if (accountsDetails == null) {
    print('No accountsDetails, loading...');
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
  organizedAccounts.sort((Map<String, dynamic> ac1, Map<String, dynamic> ac2) {
    return ac1['count'].compareTo(ac2['count']);
  });
  // Dart strings really need Python's `title` convenience method. :(
  String output = 'Developers on the ${project.substring(0, 1).toUpperCase() + project.substring(1)} project, sorted by commit count\n';
  for (Map<String, dynamic> account in organizedAccounts) {
    output += '${account['count']} - ${account['id']} - ${account['name']} - ${account['email']}\n';
  }
  new File('out/$project.txt').writeAsStringSync(output);
}

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
    return ac1['count'].compareTo(ac2['count']);
  });
  String output = 'Developers on the Fuchsia project, sorted by commit count\n';
  for (Map<String, dynamic> account in organizedAccounts) {
    output += '${account['count']} - ${account['id']} - ${account['name']} - ${account['email']}\n';
  }
  new File('out/fuchsia.txt').writeAsStringSync(output);
}

main(List<String> args) {
  // TODO: Switch on args[0] to handle arguments
  makeCombinedNamesList().then((dynamic unused){
    print("Done");
  });
}
