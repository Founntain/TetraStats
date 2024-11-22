import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:tetra_stats/data_objects/est_tr.dart';
import 'package:tetra_stats/data_objects/nerd_stats.dart';
import 'package:tetra_stats/data_objects/playstyle.dart';
import 'package:tetra_stats/data_objects/tetrio_constants.dart';
import 'package:tetra_stats/gen/strings.g.dart';
import 'package:tetra_stats/utils/numers_formats.dart';
import 'package:tetra_stats/widgets/graphs.dart';
import 'package:tetra_stats/widgets/info_thingy.dart';
import 'package:tetra_stats/widgets/nerd_stats_thingy.dart';

class DestinationCalculator extends StatefulWidget{
  final BoxConstraints constraints;

  const DestinationCalculator({super.key, required this.constraints});

  @override
  State<DestinationCalculator> createState() => _DestinationCalculatorState();
}

enum CalcCards{
  calc,
  damage
}

CalcCards calcCard = CalcCards.calc;

class ClearData{
  final String title;
  final Lineclears lineclear;
  final int lines;
  final bool miniSpin;
  final bool spin;
  bool perfectClear = false;
  int id = -1;

  ClearData(this.title, this.lineclear, this.lines, this.miniSpin, this.spin);

  ClearData cloneWith(int i){
    ClearData newOne = ClearData(title, lineclear, lines, miniSpin, spin)..id = i;
    return newOne;
  }

  bool get difficultClear {
    if (lines == 0) return false;
    if (lines >= 4 || miniSpin || spin) return true;
    else return false;
  }

  void togglePC(){
    perfectClear = !perfectClear;
  }

  int dealsDamage(int combo, int b2b, int previousB2B, Rules rules){
    if (lines == 0) return 0;
    double damage = 0;

    if (spin){
      if (lines <= 5) damage += garbage[lineclear]!;
      else damage += garbage[Lineclears.TSPIN_PENTA]! + 2 * (lines - 5);
    } else if (miniSpin){
      damage += garbage[lineclear]!;
    } else {
      if (lines <= 5) damage += garbage[lineclear]!;
      else damage += garbage[Lineclears.PENTA]! + (lines - 5);
    }

    if (difficultClear && b2b >= 1 && rules.b2b){
      if (rules.b2bChaining) damage += BACKTOBACK_BONUS * ((1 + log(1 + (b2b) * BACKTOBACK_BONUS_LOG)).floor() + (b2b == 1 ? 0 : (1 + log(1 +(b2b) * BACKTOBACK_BONUS_LOG) % 1) / 3)); // but it should be b2b-1 ???
      else damage += 1; // if b2b chaining off
    }

    if (rules.combo && rules.comboTable != ComboTables.none) {
      if (combo >= 1){
        if (lines == 1 && rules.comboTable != ComboTables.multiplier) damage += combotable[rules.comboTable]![max(0, min(combo - 1, combotable[rules.comboTable]!.length - 1))];
        else damage *= (1 + COMBO_BONUS * (combo));
      }
      if (combo >= 2) {
        damage = max(log(1 + COMBO_MINIFIER * (combo) * COMBO_MINIFIER_LOG), damage);
      }
    }

    if (!difficultClear && rules.surge && previousB2B >= rules.surgeInitAtB2b && b2b == -1){
      damage += rules.surgeInitAmount + (previousB2B - rules.surgeInitAtB2b);
    }

    if (perfectClear) damage += rules.pcDamage;

    return (damage * rules.multiplier).floor();
  }
}

Map<String, List<ClearData>> clearsExisting = {
  "No Spin Clears": [
    ClearData("No lineclear (Break Combo)", Lineclears.ZERO, 0, false, false),
    ClearData("Single", Lineclears.SINGLE, 1, false, false),
    ClearData("Double", Lineclears.DOUBLE, 2, false, false),
    ClearData("Triple", Lineclears.TRIPLE, 3, false, false),
    ClearData("Quad", Lineclears.QUAD, 4, false, false)
  ],
  "Spins": [
    ClearData("Spin Zero", Lineclears.TSPIN, 0, false, true),
    ClearData("Spin Single", Lineclears.TSPIN_SINGLE, 1, false, true),
    ClearData("Spin Double", Lineclears.TSPIN_DOUBLE, 2, false, true),
    ClearData("Spin Triple", Lineclears.TSPIN_TRIPLE, 3, false, true),
    ClearData("Spin Quad", Lineclears.TSPIN_QUAD, 4, false, true),
  ],
  "Mini spins": [
    ClearData("Mini Spin Zero", Lineclears.TSPIN_MINI, 0, true, false),
    ClearData("Mini Spin Single", Lineclears.TSPIN_MINI_SINGLE, 1, true, false),
    ClearData("Mini Spin Double", Lineclears.TSPIN_MINI_DOUBLE, 2, true, false),
    ClearData("Mini Spin Triple", Lineclears.TSPIN_MINI_TRIPLE, 3, true, false),
  ]
};

class Rules{
  bool combo = true;
  bool b2b = true;
  bool b2bChaining = false;
  bool surge = true;
  int surgeInitAmount = 4;
  int surgeInitAtB2b = 4;
  ComboTables comboTable = ComboTables.multiplier;
  int pcDamage = 5;
  int pcB2B = 1;
  double multiplier = 1.0;
}

const TextStyle mainToggleInRules = TextStyle(fontSize: 18, fontWeight: ui.FontWeight.w800);

class _DestinationCalculatorState extends State<DestinationCalculator> {
  // Stats calculator variables
  double? apm;
  double? pps;
  double? vs;
  NerdStats? nerdStats;
  EstTr? estTr;
  Playstyle? playstyle;
  TextEditingController ppsController = TextEditingController();
  TextEditingController apmController = TextEditingController();
  TextEditingController vsController = TextEditingController();

  // Damage Calculator variables
  List<Widget> rSideWidgets = [];
  List<Widget> lSideWidgets = [];
  int combo = -1;
  int b2b = -1;
  int previousB2B = -1;
  int totalDamage = 0;
  int normalDamage = 0;
  int comboDamage = 0;
  int b2bDamage = 0;
  int surgeDamage = 0;
  int pcDamage = 0;

   // values for "the bar"
  late double sec2end;
  late double sec3end;
  late double sec4end;
  late double sec5end;

  List<ClearData> clears = [];
  Map<String, int> customClearsChoice = {
    "No Spin Clears": 5,
    "Spins": 5
  };
  int idCounter = 0;
  Rules rules = Rules();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void calc() {
    apm = double.tryParse(apmController.text);
    pps = double.tryParse(ppsController.text);
    vs = double.tryParse(vsController.text);
    if (apm != null && pps != null && vs != null) {
      nerdStats = NerdStats(apm!, pps!, vs!);
      estTr = EstTr(apm!, pps!, vs!, nerdStats!.app, nerdStats!.dss, nerdStats!.dsp, nerdStats!.gbe);
      playstyle = Playstyle(apm!, pps!, nerdStats!.app, nerdStats!.vsapm, nerdStats!.dsp, nerdStats!.gbe, estTr!.srarea, estTr!.statrank);
      setState(() {});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please, enter valid values")));
    }
  }

  Widget getCalculator(){
    return SingleChildScrollView(
      child: Column(
        children: [
          if (widget.constraints.maxWidth > 768.0) Card(
            child: Center(child: Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Column(
                children: [
                  Text("Stats Calucator", style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            )),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
              child: Row(
                children: [
                  //TODO: animate those TextFields
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 0.0),
                      child: TextField(
                        onSubmitted: (value) => calc(),
                        onChanged: (value) {setState(() {});},
                        controller: apmController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(suffix: apmController.value.text.isNotEmpty ? Text("APM") : null, alignLabelWithHint: true, hintText: widget.constraints.maxWidth > 768.0 ? "Enter your APM" : "APM"),
                      ),
                    )
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 0.0),
                      child: TextField(
                        onSubmitted: (value) => calc(),
                        onChanged: (value) {setState(() {});},
                        controller: ppsController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(suffix: ppsController.value.text.isNotEmpty ? Text("PPS") : null, alignLabelWithHint: true, hintText: widget.constraints.maxWidth > 768.0 ? "Enter your PPS" : "PPS"),
                      ),
                    )
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 0.0),
                      child: TextField(
                        onSubmitted: (value) => calc(),
                        onChanged: (value) {setState(() {});},
                        controller: vsController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(suffix: vsController.value.text.isNotEmpty ? Text("VS") : null, alignLabelWithHint: true, hintText: widget.constraints.maxWidth > 768.0 ? "Enter your VS" : "VS"),
                      ),
                    )
                  ),
                  TextButton(
                    onPressed: () => calc(),
                    child: Text(t.calc),
                  ),
                ],
              ),
            ),
          ),
          if (nerdStats != null) Card(
            child: NerdStatsThingy(nerdStats: nerdStats!, width: widget.constraints.minWidth)
          ),
          if (playstyle != null) Card(
            child: Graphs(apm!, pps!, vs!, nerdStats!, playstyle!)
          ),
          if (nerdStats == null) InfoThingy("Enter values and press \"Calc\" to see Nerd Stats for them")
        ],
      ),
    );
  }

  Widget rSideDamageCalculator(double width, bool hasSidebar){
    return SizedBox(
      width: width - (hasSidebar ? 80 : 0),
      height: widget.constraints.maxHeight - (hasSidebar ? 108 : 178),
      child: clears.isEmpty ? InfoThingy("Click on the actions on the left to add them here") :
      Card(
        child: Column(
          children: [
            Expanded(
              child: ReorderableListView(
                onReorder: (oldIndex, newIndex) {
                  setState((){
                    if (oldIndex < newIndex) {
                      newIndex -= 1;
                    }
                    final ClearData item = clears.removeAt(oldIndex);
                    clears.insert(newIndex, item);
                  });
                },
                children: lSideWidgets,
              ),
            ),
            Divider(),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 0.0, 34.0, 0.0),
                  child: Row(
                    children: [
                      Text("Total damage:", style: TextStyle(fontSize: 36, fontWeight: ui.FontWeight.w100)),
                      Spacer(),
                      Text(intf.format(totalDamage), style: TextStyle(fontFamily: "Eurostile Round Extended", fontSize: 36, fontWeight: ui.FontWeight.w100))
                    ],
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text("Lineclears: ${intf.format(normalDamage)}"),
                    Text("Combo: ${intf.format(comboDamage)}"),
                    Text("B2B: ${intf.format(b2bDamage)}"),
                    Text("Surge: ${intf.format(surgeDamage)}"),
                    Text("PCs: ${intf.format(pcDamage)}")
                  ],
                ),
                if (totalDamage > 0) SfLinearGauge(
                  minimum: 0,
                  maximum: totalDamage.toDouble(),
                  showLabels: false,
                  showTicks: false,
                  ranges: [
                    LinearGaugeRange(
                      color: Colors.green,
                      startValue: 0,
                      endValue: normalDamage.toDouble(),
                      position: LinearElementPosition.cross,
                    ),
                    LinearGaugeRange(
                      color: Colors.yellow,
                      startValue: normalDamage.toDouble(),
                      endValue: sec2end,
                      position: LinearElementPosition.cross,
                    ),
                    LinearGaugeRange(
                      color: Colors.blue,
                      startValue: sec2end,
                      endValue: sec3end,
                      position: LinearElementPosition.cross,
                    ),
                    LinearGaugeRange(
                      color: Colors.red,
                      startValue: sec3end,
                      endValue: sec4end,
                      position: LinearElementPosition.cross,
                    ),
                    LinearGaugeRange(
                      color: Colors.orange,
                      startValue: sec4end,
                      endValue: sec5end,
                      position: LinearElementPosition.cross,
                    ),
                  ],
                ),
                ElevatedButton.icon(onPressed: (){setState((){clears.clear();});}, icon: const Icon(Icons.clear), label: Text("Clear all"), style: const ButtonStyle(shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12.0))))))
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget getDamageCalculator(){
    rSideWidgets = [];
    lSideWidgets = [];
    for (var key in clearsExisting.keys){
      rSideWidgets.add(Text(key));
      for (ClearData data in clearsExisting[key]!) rSideWidgets.add(Card(
        child: ListTile(
          title: Text(data.title),
          subtitle: Text("${data.dealsDamage(0, 0, 0, rules)} damage${data.difficultClear ? ", difficult" : ""}", style: TextStyle(color: Colors.grey)),
          trailing: Icon(Icons.arrow_forward_ios),
          onTap: (){
            setState((){
              clears.add(data.cloneWith(idCounter));
            });
            idCounter++;
          },
        ),
      ));
      if (key != "Mini spins") rSideWidgets.add(Card(
        child: ListTile(
          title: Text("Custom"),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 30.0, child: TextField(
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(hintText: "5"),
                onChanged: (value) => customClearsChoice[key] = int.parse(value),
              )),
              Text(" Lines", style: Theme.of(context).textTheme.displayLarge),
              Icon(Icons.arrow_forward_ios)
            ],
          ),
          onTap: (){
            setState((){
              clears.add(ClearData("${key == "Spins" ? "Spin " : ""}${clearNames[min(customClearsChoice[key]!, clearNames.length-1)]} (${customClearsChoice[key]!} Lines)", key == "Spins" ? Lineclears.TSPIN_PENTA : Lineclears.PENTA, customClearsChoice[key]!, false, key == "Spins").cloneWith(idCounter));
            });
            idCounter++;
          },
        ),
      ));
      rSideWidgets.add(const Divider());
    }

    combo = -1;
    b2b = -1;
    previousB2B = -1;
    totalDamage = 0;
    normalDamage = 0;
    comboDamage = 0;
    b2bDamage = 0;
    surgeDamage = 0;
    pcDamage = 0;

    for (ClearData lineclear in clears){
      previousB2B = b2b;
      if (lineclear.difficultClear) b2b++; else if (lineclear.lines > 0) b2b = -1;
      if (lineclear.lines > 0) combo++; else combo = -1;
      int pcDmg = lineclear.perfectClear ? (rules.pcDamage * rules.multiplier).floor() : 0;
      int normalDmg = lineclear.dealsDamage(0, 0, 0, rules) - pcDmg;
      int surgeDmg = (!lineclear.difficultClear && rules.surge && previousB2B >= rules.surgeInitAtB2b && b2b == -1) ? rules.surgeInitAmount + (previousB2B - rules.surgeInitAtB2b) : 0;
      int b2bDmg = lineclear.dealsDamage(0, b2b, b2b-1, rules) - normalDmg - pcDmg;
      int dmg = lineclear.dealsDamage(combo, b2b, previousB2B, rules);
      int comboDmg = dmg - normalDmg - b2bDmg - surgeDmg - pcDmg;
      lSideWidgets.add(
        ListTile(
          key: ValueKey(lineclear.id),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(onPressed: (){ setState((){clears.removeWhere((element) => element.id == lineclear.id,);}); }, icon: Icon(Icons.clear)),
              if (lineclear.lines > 0) IconButton(onPressed: (){ setState((){lineclear.togglePC();}); }, icon: Icon(Icons.local_parking_outlined, color: lineclear.perfectClear ? Colors.white : Colors.grey.shade800)),
            ],
          ),
          title: Text("${lineclear.title}${lineclear.perfectClear ? " PC" : ""}${combo > 0 ? ", ${combo} combo" : ""}${b2b > 0 ? ", B2Bx${b2b}" : ""}"),
          subtitle: lineclear.lines > 0 ? Text("${dmg == normalDmg ? "No bonuses" : ""}${b2bDmg > 0 ? "+${intf.format(b2bDmg)} for B2B" : ""}${(b2bDmg > 0 && comboDmg > 0) ? ", " : ""}${comboDmg > 0 ? "+${intf.format(comboDmg)} for combo" : ""}${(comboDmg > 0 && lineclear.perfectClear) ? ", " : ""}${lineclear.perfectClear ? "+${intf.format(pcDmg)} for PC" : ""}${(surgeDmg > 0 && (lineclear.perfectClear || comboDmg > 0)) ? ", " : ""}${surgeDmg > 0 ? "Surge released: +${intf.format(surgeDmg)}" : ""}", style: TextStyle(color: Colors.grey)) : null,
          trailing: lineclear.lines > 0 ? Padding(
            padding: const EdgeInsets.only(right: 10.0),
            child: Text(dmg.toString(), style: TextStyle(fontSize: 36, fontWeight: ui.FontWeight.w100)),
          ) : null,
        )
      );
      totalDamage += dmg;
      normalDamage += normalDmg;
      comboDamage += comboDmg;
      b2bDamage += b2bDmg;
      surgeDamage += surgeDmg;
      pcDamage += pcDmg;
    }
    // values for "the bar"
    sec2end = normalDamage.toDouble()+comboDamage.toDouble();
    sec3end = normalDamage.toDouble()+comboDamage.toDouble()+b2bDamage.toDouble();
    sec4end = normalDamage.toDouble()+comboDamage.toDouble()+b2bDamage.toDouble()+surgeDamage.toDouble();
    sec5end = normalDamage.toDouble()+comboDamage.toDouble()+b2bDamage.toDouble()+surgeDamage.toDouble()+pcDamage.toDouble();
    return Column(
      children: [
        if (widget.constraints.maxWidth > 768.0) Card(
          child: Center(child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Column(
              children: [
                Text("Damage Calucator", style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          )),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: widget.constraints.maxWidth > 768.0 ? 350.0 : widget.constraints.maxWidth,
                child: DefaultTabController(length: widget.constraints.maxWidth > 768.0 ? 2 : 3,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Card(
                        child: TabBar(tabs: [
                          Tab(text: "Actions"),
                          if (widget.constraints.maxWidth <= 768.0) Tab(text: "Results"),
                          Tab(text: "Rules"),
                        ]),
                      ),
                      SizedBox(
                        height: widget.constraints.maxHeight - 164,
                        child: TabBarView(children: [
                          SingleChildScrollView(
                            child: Column(
                              children: rSideWidgets,
                            ),
                          ),
                          if (widget.constraints.maxWidth <= 768.0) SingleChildScrollView(
                            child: rSideDamageCalculator(widget.constraints.minWidth, false),
                          ),
                          SingleChildScrollView(
                            child: Column(
                              children: [
                                Card(
                                  child: Column(
                                    children: [
                                      ListTile(
                                        title: Text("Multiplier", style: mainToggleInRules),
                                        trailing: SizedBox(width: 90.0, child: TextField(
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                                          decoration: InputDecoration(hintText: rules.multiplier.toString()),
                                          onChanged: (value) => setState((){rules.multiplier = double.parse(value);}),
                                        )),
                                      ),
                                      ListTile(
                                        title: Text("Perfect Clear Damage"),
                                        trailing: SizedBox(width: 90.0, child: TextField(
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))],
                                          decoration: InputDecoration(hintText: rules.pcDamage.toString()),
                                          onChanged: (value) => setState((){rules.pcDamage = int.parse(value);}),
                                        )),
                                      ),
                                    ],
                                  ),
                                ),
                                Card(
                                  child: Column(
                                    children: [
                                      ListTile(
                                        title: Text("Combo", style: mainToggleInRules),
                                        trailing: Switch(value: rules.combo, onChanged: (v) => setState((){rules.combo = v;})),
                                      ),
                                      if (rules.combo) ListTile(
                                        title: Text("Combo Table"),
                                        trailing: DropdownButton(
                                          items: [for (var v in ComboTables.values) if (v != ComboTables.none) DropdownMenuItem(value: v.index, child: Text(comboTablesNames[v]!))],
                                          value: rules.comboTable.index,
                                          onChanged: (v) => setState((){rules.comboTable = ComboTables.values[v!];}),
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                                Card(
                                  child: Column(
                                    children: [
                                      ListTile(
                                        title: Text("Back-To-Back (B2B)", style: mainToggleInRules),
                                        trailing: Switch(value: rules.b2b, onChanged: (v) => setState((){rules.b2b = v;})),
                                      ),
                                      if (rules.b2b) ListTile(
                                        title: Text("Back-To-Back Chaining"),
                                        trailing: Switch(value: rules.b2bChaining, onChanged: (v) => setState((){rules.b2bChaining = v;})),
                                      ),
                                    ],
                                  ),
                                ),
                                Card(
                                  child: Column(
                                    children: [
                                      ListTile(
                                        title: Text("Surge", style: mainToggleInRules),
                                        trailing: Switch(value: rules.surge, onChanged: (v) => setState((){rules.surge = v;})),
                                      ),
                                      if (rules.surge) ListTile(
                                        title: Text("Starts at B2B"),
                                        trailing: SizedBox(width: 90.0, child: TextField(
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                          decoration: InputDecoration(hintText: rules.surgeInitAtB2b.toString()),
                                          onChanged: (value) => setState((){rules.surgeInitAtB2b = int.parse(value);}),
                                        )),
                                      ),
                                      if (rules.surge) ListTile(
                                        title: Text("Start amount"),
                                        trailing: SizedBox(width: 90.0, child: TextField(
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                          decoration: InputDecoration(hintText: rules.surgeInitAmount.toString()),
                                          onChanged: (value) => setState((){rules.surgeInitAmount = int.parse(value);}),
                                        )),
                                      ),
                                    ],
                                  ),
                                )
                              ],
                            ),
                          ),
                        ]),
                      )
                    ],
                  )
                ),
              ),
              if (widget.constraints.maxWidth > 768.0) rSideDamageCalculator(widget.constraints.maxWidth - 350, true)
            ],
          ),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: widget.constraints.maxHeight - (widget.constraints.maxWidth > 768.0 ? 32 : 133),
          child: switch (calcCard){
            CalcCards.calc => getCalculator(),
            CalcCards.damage => getDamageCalculator()
          } 
        ),
        if (widget.constraints.maxWidth > 768.0) SegmentedButton<CalcCards>(
          showSelectedIcon: false,
          segments: <ButtonSegment<CalcCards>>[
            const ButtonSegment<CalcCards>(
                value: CalcCards.calc,
                label: Text('Stats Calculator'),
                ),
            ButtonSegment<CalcCards>(
                value: CalcCards.damage,
                label: Text('Damage Calculator'),
                ),
          ],
          selected: <CalcCards>{calcCard},
          onSelectionChanged: (Set<CalcCards> newSelection) {
            setState(() {
              calcCard = newSelection.first;
            });})
      ],
    );
  }

}
