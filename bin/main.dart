import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart';

bool _debugging = true;

String makeCookie(Map<String, dynamic> cookies){
  String cookie = "";
  cookies.forEach((String key, dynamic value) {
    cookie += "$key=$value; ";
  });
  // Strip the trailing semicolon and space.
  if (cookie.length > 0)
    return cookie.substring(0, cookie.length - 2);
  return null;
}

Future<List<Map<String, dynamic>>> scrape(String endpoint, Map<String, dynamic> params, {Map<String, dynamic> cookies}) async {
  Uri url = new Uri(
    scheme: "https",
    host: "fuchsia-review.googlesource.com",
    path: endpoint,
    queryParameters: params,
  );
  // TODO: Double-check cookies functionality.
  print("Scraping ${cookies != null ? "with" : "without"} cookies: ${url.toString()}");
  Response res = await get(url, headers: {"Cookie": makeCookie(cookies)});
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
    new File('${project}_changes_${DateTime.now().toIso8601String()}.json').writeAsStringSync(json.encode(entries));
  }
  return entries;
}

Future<Map<int, int>> getAccountIDs({String project = "garnet"}) async {
  Map<int, int> accountChanges = {};
  List<Map<String, dynamic>> changes = await getChanges(project);
  for (Map<String, dynamic> change in changes) {
    if (accountChanges.containsKey(change["owner"])) {
      accountChanges[change["owner"]]++;
    } else {
      accountChanges[change["owner"]] = 1;
    }
  }
  if (_debugging) {
    new File('${project}_accounts_${DateTime.now().toIso8601String()}.json').writeAsStringSync(json.encode(accountChanges));
  }
  return accountChanges;
}
