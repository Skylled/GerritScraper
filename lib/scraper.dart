import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart';
import 'caching.dart';

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
Future<Map<String, dynamic>> scrapeAccount(String accountID, {cached = true}) async {
  if (!cacheLoaded)
    loadAccountCache();
  if (cached && cachedAccounts.containsKey(accountID)) {
    return cachedAccounts[accountID];
  }
  // print('Scraping for account: $accountID');
  Response res = await get('https://fuchsia-review.googlesource.com/accounts/$accountID', headers: {'Cookie': makeCookie()});
  if (res.statusCode == HttpStatus.OK) {
    Map decJson = json.decode(res.body.substring(5));
    Map<String, dynamic> newAccount = decJson.cast<String, dynamic>();
    cachedAccounts[accountID] = newAccount;
    accountsCacheFile.writeAsStringSync(json.encode(cachedAccounts));
    return newAccount;
  } else {
    throw new HttpException('Status code: ${res.statusCode}');
  }
}

Future<bool> scrapeAndroidChanges(String email) async {
  Response res = await get('https://android-review.googlesource.com/changes/?q=$email&n=10');
  if (res.statusCode == HttpStatus.OK) {
    List decJson = json.decode(res.body.substring(5));
    List<Map<String, dynamic>> foundChanges = decJson.cast<Map<String, dynamic>>();
    if (foundChanges.length > 0) {
      return true;
    }
    return false;
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
