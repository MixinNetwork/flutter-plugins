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
        """
insert into t1(x) values
 ('周杰伦 Jay Chou:我已分不清，你是友情还是错过的爱情'), 
('周杰伦 Jay Chou:最美的不是下雨天，是曾与你躲过雨的屋檐'),
 ('I love China! 我爱中国！我是中华人民共和国公民！'),
  ('@English &special _characters."''bacon-&and''-eggs%'),
  ('政府は30日、世界文化遺産への登録を目指す「富士山」（山梨県、静岡県）について、国連教育科学文化機関（ユネスコ）の諮問機関から登録を求める勧告が出たと発表した。構成資産の一つ、三保松原（静岡市）の除外が条件。ユネスコが６月にカンボジアで開く世界遺産委員会が最終決定する。勧告が覆った例は少なく、登録されれば国内で17件目の世界遺産になる。'),
  ('서는 안될 정도로 꼭 요긴한 것들 만일까? 살펴볼수록 없어도 좋을 만한 것들이 적지 않다.')
  """);
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
