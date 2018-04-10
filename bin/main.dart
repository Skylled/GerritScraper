import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart';

bool _debugging = true;

// Future: Generate XSRF_TOKEN legitimately.

String makeCookie(){
  Map<String, dynamic> cookies = json.decode(new File('cookies.json').readAsStringSync());
  String cookie = "";
  cookies.forEach((String key, dynamic value) {
    cookie += "$key=$value; ";
  });
  // Strip the trailing semicolon and space.
  if (cookie.length > 0)
    return cookie.substring(0, cookie.length - 2);
  return null;
}

Future<Map<String, dynamic>> scrapeAccount(int accountID) async {
  Response res = await get("https://fuchsia-review.googlesource.com/accounts/$accountID", headers: {"Cookie": makeCookie()});
  return json.decode(res.body);
}

Future<List<Map<String, dynamic>>> scrape(String endpoint, Map<String, dynamic> params) async {
  Uri url = new Uri(
    scheme: "https",
    host: "fuchsia-review.googlesource.com",
    path: endpoint,
    queryParameters: params,
  );
  // TODO: Double-check cookies functionality.
  print("Scraping: ${url.toString()}");
  Response res = await get(url);
  return json.decode(res.body);
}

Future<List<Map<String, dynamic>>> getChanges(String project) async {
  String query = 'project:$project status:merged -roll';
  int start = 0;
  List<Map<String, dynamic>> entries = [];
  while (true) {
    List<Map<String, dynamic>> newEntries = await scrape('changes', {'q': query, 'S': start});
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

Future<Map<int, int>> getAccountChanges(String project, {List<Map<String, dynamic>> changes}) async {
  Map<int, int> accountChanges = {};
  if (changes == null) {
    changes = await getChanges(project ?? "garnet");
  }
  for (Map<String, dynamic> change in changes) {
    if (accountChanges.containsKey(change["owner"])) {
      accountChanges[change["owner"]]++;
    } else {
      accountChanges[change["owner"]] = 1;
    }
  }
  if (_debugging) {
    new File('logs/${project ?? "unknown"}_account_changes_${DateTime.now().toIso8601String()}.json').writeAsStringSync(json.encode(accountChanges));
  }
  return accountChanges;
}

Future<Map<int, Map<String, dynamic>>> getAccountNames(String project, {Map<int, int> accountChanges}) async {
  Map<int, Map<String, dynamic>> accounts = {};
  if (accountChanges == null) {
    print("No accountChanges, loading...");
    accountChanges = await getAccountChanges(project);
  }
  await accountChanges.forEach((int accountID, int changes) async {
    Map<String, dynamic> accountDetails = await scrapeAccount(accountID);
    accounts[accountID] = accountDetails;
  });
  if (_debugging) {
    new File('logs/${project ?? "unknown"}_account_details_${DateTime.now().toIso8601String()}.json').writeAsStringSync(json.encode(accounts));
  }
  return accounts;
}

main(List<String> args) {
  // TODO: Switch on args[0] to handle arguments
  getAccountNames("docs").then((Map<int, Map<String, dynamic>> accounts) {
    print("Done & logged.");
  });
}
