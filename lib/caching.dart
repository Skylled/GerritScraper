import 'dart:convert';
import 'dart:io';

Map<String, Map<String, dynamic>> cachedAccounts;
bool cacheLoaded = false;
File accountsCacheFile;

void loadAccountCache(){
  accountsCacheFile = new File('cache/accounts.json');
  if (!accountsCacheFile.existsSync()) {
    accountsCacheFile.createSync(recursive: true);
    accountsCacheFile.writeAsStringSync('{}');
  }
  Map decJson = json.decode(accountsCacheFile.readAsStringSync());
  cachedAccounts = decJson.cast<String, Map<String, dynamic>>();
  cacheLoaded = true;
}