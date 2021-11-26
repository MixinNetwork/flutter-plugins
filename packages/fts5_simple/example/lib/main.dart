import 'package:flutter/material.dart';
import 'package:fts5_simple/fts5_simple.dart';
import 'package:sqlite3/sqlite3.dart' hide Row;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final db = sqlite3.openInMemory();

  final TextEditingController _controller = TextEditingController();

  String? _dashboard;

  bool _enableJieBa = false;

  @override
  void initState() {
    super.initState();
    db.loadSimpleExtension();
    // create table
    db.execute("CREATE VIRTUAL TABLE t1 USING fts5(x, tokenize = 'simple')");
    // insert some data
    db.execute(
        "insert into t1(x) values ('周杰伦 Jay Chou:我已分不清，你是友情还是错过的爱情'), ('周杰伦 Jay Chou:最美的不是下雨天，是曾与你躲过雨的屋檐'), ('I love China! 我爱中国！我是中华人民共和国公民！'), ('@English &special _characters.\"''bacon-&and''-eggs%')");
  }

  @override
  void dispose() {
    db.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: TextField(controller: _controller),
              ),
              SwitchListTile(
                value: _enableJieBa,
                onChanged: (value) {
                  setState(() {
                    _enableJieBa = value;
                  });
                },
                title: const Text('Enable JieBa'),
              ),
              TextButton(
                onPressed: () {
                  final queryType =
                      _enableJieBa ? 'jieba_query' : 'simple_query';
                  final ret = db.select(
                      "select rowid as id, simple_highlight(t1, 0, '[', ']')"
                      " as info from t1 where x match $queryType(?)",
                      [_controller.text]);
                  setState(() {
                    _dashboard = ret.toString();
                  });
                },
                child: const Text('Search'),
              ),
              if (_dashboard != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    _dashboard!,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
