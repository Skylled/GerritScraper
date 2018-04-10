import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart';

bool _debugging = true;

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
  print("Scraping for account: $accountID");
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

Future<Map<String, Map<String, dynamic>>> getAccountsDetails(String project, {Map<String, int> accountsChanges}) async {
  Map<String, Map<String, dynamic>> accounts = {};
  if (accountsChanges == null) {
    print('No accountChanges, loading...');
    accountsChanges = await getAccountsChanges(project);
  }
  await accountsChanges.forEach((String accountID, int changes) async {
    Map<String, dynamic> accountDetails = await scrapeAccount(accountID);
    accounts[accountID] = accountDetails;
  });
  List<Future> futures = [];
  accountsChanges.forEach((String accountID, int changes){
    futures.add(() async {
      accounts[accountID] = await scrapeAccount(accountID);
    }());
  });
  await Future.wait(futures);
  if (_debugging) {
    new File('logs/${project ?? 'unknown'}_account_details_${DateTime.now().toIso8601String()}.json').writeAsStringSync(json.encode(accounts));
  }
  return accounts;
}

// How do I want info organized in its final state?

main(List<String> args) {
  // TODO: Switch on args[0] to handle arguments
  getAccountsDetails('garnet');
}
