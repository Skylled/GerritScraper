import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart';

String makeCookie(Map<String, dynamic> cookies){
  String cookie = "";
  cookies.forEach((String key, dynamic value) {
    cookie += "$key=$value; ";
  });
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
  Response res = await get(url, headers: {"Cookie": makeCookie(cookies)});
  return json.decode(res.body);
}

Future<List<Map<String, dynamic>>> getChanges({String project = "garnet"}) async {
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
  return entries;
}

Future<Map<int, int>> getAccountIDs() async {
  Map<int, int> accountChanges = {};
  List<Map<String, dynamic>> changes = await getChanges();
  for (Map<String, dynamic> change in changes) {
    if (accountChanges.containsKey(change["owner"])) {
      accountChanges[change["owner"]]++;
    } else {
      accountChanges[change["owner"]] = 1;
    }
  }
  return accountChanges;
}