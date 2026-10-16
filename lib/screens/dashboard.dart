part of '../main.dart';

// Dashboard read-only: nunca altera faturas, compras ou parsers.
class TelaDashboard extends StatefulWidget {
  const TelaDashboard({super.key});
  @override
  State<TelaDashboard> createState() => _TelaDashboardState();
}

class _TelaDashboardState extends State<TelaDashboard> {
  late Future<List<Map<String, dynamic>>> _historico;
  String _categoria = 'Todas';
  String _cartao = 'Todos';
  bool _mostrarReal = true;
  bool _mostrarProjetado = true;
  String? _mesSelecionado;

  @override
  void initState() {
    super.initState();
    _historico = HistoricoLocal.listar();
  }

  static String _mes(String vencimento) {
    final m = RegExp(r'^\d{2}/(\d{2})/(\d{4})$').firstMatch(vencimento.trim());
    if (m == null) return '';
    final mm = int.tryParse(m.group(1)!) ?? 0;
    if (mm < 1 || mm > 12) return '';
    return '${m.group(2)}-${mm.toString().padLeft(2, '0')}';
  }

  static String _somarMeses(String mes, int quantidade) {
    final partes = mes.split('-');
    final d = DateTime(int.parse(partes[0]), int.parse(partes[1]) + quantidade);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}';
  }

  static String _moeda(int centavos) {
    final v = (centavos.abs() / 100).toStringAsFixed(2).replaceAll('.', ',');
    return '${centavos < 0 ? '-' : ''}R\$ $v';
  }

  static String _categoriaDaCompra(Map<String, dynamic> e) {
    final informada = '${e['categoria'] ?? ''}'.trim();
    final normal = ParserItau.chave(informada);
    if (normal.isNotEmpty && normal != 'outros') return informada;
    // Classificação auxiliar apenas para visualização, sem reescrever o histórico.
    final desc = ParserItau.chave('${e['descricao'] ?? ''}');
    if (RegExp(r'farmacia|drogaria|droga\w*|pague\w*menos|raia|drogasil').hasMatch(desc)) return 'Farmácia';
    if (RegExp(r'posto|combustivel|gasolina|etanol|shell|ipiranga|petrobras').hasMatch(desc)) return 'Combustível';
    if (RegExp(r'restaurante|lanchonete|pizzaria|ifood|burger|mcdonald').hasMatch(desc)) return 'Restaurante';
    if (RegExp(r'mercado|supermercado|atacadao|carrefour|assai').hasMatch(desc)) return 'Supermercado';
    return informada.isEmpty ? 'Outros' : informada;
  }

  static String _chaveParcela(Map<String, dynamic> e) => [
    e['cartao'], ParserItau.chave('${e['descricao']}'),
    e['atual'] ?? 0, e['total'] ?? 0, e['centavos'], e['mes'],
  ].join('|');

  static List<Map<String, dynamic>> _lancamentos(List<Map<String, dynamic>> faturas) {
    final reais = <Map<String, dynamic>>[];
    final reaisChaves = <String>{};
    for (final f in faturas) {
      final mes = _mes('${f['vencimento'] ?? ''}');
      if (mes.isEmpty) continue;
      final cartao = '${f['cartao'] ?? ''}';
      for (final raw in (f['compras'] as List? ?? const [])) {
        final e = Map<String, dynamic>.from(raw as Map);
        final item = <String, dynamic>{
          'mes': mes, 'cartao': cartao,
          'vencimento': '${f['vencimento'] ?? ''}',
          'dataCompra': DatasFatura.dataCompra('${e['data'] ?? ''}',
              '${f['vencimento'] ?? ''}', (e['parcelaAtual'] as num?)?.toInt()),
          'descricao': '${e['descricao'] ?? ''}',
          'categoria': _categoriaDaCompra(e),
          'centavos': (e['valorCentavos'] as num?)?.toInt() ?? 0,
          'atual': (e['parcelaAtual'] as num?)?.toInt(),
          'total': (e['totalParcelas'] as num?)?.toInt(),
          'situacao': 'Realizado',
        };
        reais.add(item);
        reaisChaves.add(_chaveParcela(item));
      }
    }
    // Mesmo critério da exportação Fase 3: a parcela mais recente gera o futuro.
    final ultimas = <String, Map<String, dynamic>>{};
    for (final item in reais) {
      final atual = item['atual'] as int?;
      final total = item['total'] as int?;
      if (atual == null || total == null || atual < 1 || total <= atual || total > 60) continue;
      final grupo = [item['cartao'], ParserItau.chave(item['descricao'] as String), total, item['centavos']].join('|');
      final anterior = ultimas[grupo];
      if (anterior == null || atual > (anterior['atual'] as int) ||
          (atual == anterior['atual'] && (item['mes'] as String).compareTo(anterior['mes'] as String) > 0)) {
        ultimas[grupo] = item;
      }
    }
    final projetadas = <Map<String, dynamic>>[];
    final chavesProjetadas = <String>{};
    for (final item in ultimas.values) {
      final atual = item['atual'] as int;
      final total = item['total'] as int;
      for (var p = atual + 1; p <= total; p++) {
        final futuro = <String, dynamic>{
          ...item,
          'mes': _somarMeses(item['mes'] as String, p - atual),
          'vencimento': DatasFatura.vencimentoParcela(
              item['vencimento'] as String, p - atual),
          'atual': p,
          'situacao': 'Projetado',
        };
        final chave = _chaveParcela(futuro);
        if (!reaisChaves.contains(chave) && chavesProjetadas.add(chave)) projetadas.add(futuro);
      }
    }
    return [...reais, ...projetadas];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Dashboard de despesas')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _historico,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError) return Center(child: Text('Erro ao carregar histórico: ${snapshot.error}'));
          return const Center(child: CircularProgressIndicator());
        }
        final itens = _lancamentos(snapshot.data!);
        if (itens.isEmpty) return const Center(child: Text('Importe uma fatura conciliada para visualizar o dashboard.'));
        final categoriasDisponiveis = {for (final e in itens) e['categoria'] as String}.toList()..sort();
        final cartoesDisponiveis = {for (final e in itens) e['cartao'] as String}.toList()..sort();
        final categorias = ['Todas', ...categoriasDisponiveis];
        final cartoes = ['Todos', ...cartoesDisponiveis];
        final categoria = categorias.contains(_categoria) ? _categoria : 'Todas';
        final cartao = cartoes.contains(_cartao) ? _cartao : 'Todos';
        final filtrados = itens.where((e) =>
          (categoria == 'Todas' || e['categoria'] == categoria) &&
          (cartao == 'Todos' || e['cartao'] == cartao)).toList();
        final porMes = <String, List<Map<String, dynamic>>>{};
        for (final e in filtrados) { (porMes[e['mes'] as String] ??= []).add(e); }
        final meses = porMes.keys.toList()..sort();
        final totais = <String, List<int>>{};
        for (final mes in meses) {
          var real = 0;
          var projetado = 0;
          for (final e in porMes[mes]!) {
            if (e['situacao'] == 'Realizado') { real += e['centavos'] as int; }
            else { projetado += e['centavos'] as int; }
          }
          totais[mes] = [real, projetado];
        }
        final totalReal = totais.values.fold<int>(0, (s, e) => s + e[0]);
        final totalProjetado = totais.values.fold<int>(0, (s, e) => s + e[1]);
        final selecionado = meses.contains(_mesSelecionado) ? _mesSelecionado : (meses.isEmpty ? null : meses.last);
        final detalhes = selecionado == null ? <Map<String, dynamic>>[] :
          porMes[selecionado]!.where((e) =>
            (e['situacao'] == 'Realizado' && _mostrarReal) ||
            (e['situacao'] == 'Projetado' && _mostrarProjetado)).toList();
        detalhes.sort((a,b) => (a['descricao'] as String).compareTo(b['descricao'] as String));
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Evolução mensal', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: categoria, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Categoria', border: OutlineInputBorder()),
            items: categorias.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() { _categoria = v ?? 'Todas'; _mesSelecionado = null; }),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: cartao, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Cartão', border: OutlineInputBorder()),
            items: cartoes.map((v) => DropdownMenuItem(value: v, child: Text(v.isEmpty ? 'Não identificado' : v))).toList(),
            onChanged: (v) => setState(() { _cartao = v ?? 'Todos'; _mesSelecionado = null; }),
          ),
          Wrap(spacing: 12, children: [
            FilterChip(label: const Text('Realizado'), selected: _mostrarReal,
              onSelected: (v) => setState(() => _mostrarReal = v)),
            FilterChip(label: const Text('Projetado'), selected: _mostrarProjetado,
              onSelected: (v) => setState(() => _mostrarProjetado = v)),
          ]),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Chip(label: Text('Realizado: ${_moeda(totalReal)}')),
            Chip(label: Text('Projetado: ${_moeda(totalProjetado)}')),
          ]),
          const Text('Barras empilhadas: azul = realizado; laranja = projetado.'),
          const SizedBox(height: 8),
          if (meses.isEmpty) const Text('Nenhum lançamento para o filtro escolhido.')
          else SizedBox(height: 280, child: LayoutBuilder(builder: (context, constraints) {
            const larguraBarra = 52.0;
            final largura = meses.length * larguraBarra + 44.0;
            return SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(
              width: largura < constraints.maxWidth ? constraints.maxWidth : largura,
              child: CustomPaint(painter: _PintorBarrasEmpilhadas(
                meses: meses, totais: totais, mostrarReal: _mostrarReal,
                mostrarProjetado: _mostrarProjetado, selecionado: selecionado,
              )),
            ));
          })),
          const SizedBox(height: 12),
          if (meses.isNotEmpty) DropdownButtonFormField<String>(
            value: selecionado, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Detalhar mês', border: OutlineInputBorder()),
            items: meses.map((m) => DropdownMenuItem(value: m, child: Text('${m.substring(5)}/${m.substring(0,4)}'))).toList(),
            onChanged: (v) => setState(() => _mesSelecionado = v),
          ),
          const SizedBox(height: 8),
          ...detalhes.map((e) => ListTile(
            dense: true,
            title: Text('${e['descricao']}'),
            subtitle: Text('${e['categoria']} • ${e['situacao']} • ${e['cartao']}'
              '${e['atual'] == null ? '' : ' • ${e['atual']}/${e['total']}'}'
              '\nCompra: ${e['dataCompra'] == '' ? 'Não informada' : e['dataCompra']}'
              ' • Vencimento: ${e['vencimento'] == '' ? 'Não identificado' : e['vencimento']}'),
            trailing: Text(_moeda(e['centavos'] as int)),
          )),
          const SizedBox(height: 12),
          const Text('Projeções são estimativas, não lançamentos faturados. A classificação por descrição é aproximada. Compras parceladas idênticas podem ser agrupadas indevidamente.'),
        ]);
      },
    ),
  );
}

class _PintorBarrasEmpilhadas extends CustomPainter {
  final List<String> meses;
  final Map<String, List<int>> totais;
  final bool mostrarReal;
  final bool mostrarProjetado;
  final String? selecionado;
  _PintorBarrasEmpilhadas({required this.meses, required this.totais,
    required this.mostrarReal, required this.mostrarProjetado, required this.selecionado});

  @override
  void paint(Canvas canvas, Size size) {
    const left = 42.0;
    const bottom = 35.0;
    const top = 18.0;
    final areaH = size.height - bottom - top;
    final areaW = size.width - left - 8;
    final maximo = meses.fold<int>(0, (m, mes) {
      final v = totais[mes]!;
      final total = (mostrarReal ? v[0] : 0) + (mostrarProjetado ? v[1] : 0);
      return total > m ? total : m;
    });
    final escala = maximo <= 0 ? 1.0 : maximo * 1.12;
    final eixo = Paint()..color = const Color(0xffcccccc)..strokeWidth = 1;
    final texto = TextPainter(textDirection: TextDirection.ltr);
    void escrever(String s, double x, double y, {double fontSize = 10, Color cor = const Color(0xff666666)}) {
      texto.text = TextSpan(text: s, style: TextStyle(fontSize: fontSize, color: cor));
      texto.layout();
      texto.paint(canvas, Offset(x, y));
    }
    for (var i = 0; i <= 4; i++) {
      final y = top + areaH * (1 - i / 4);
      canvas.drawLine(Offset(left, y), Offset(size.width - 4, y), eixo);
      escrever('${((escala * i / 4) / 100).round()}', 2, y - 7);
    }
    final passo = areaW / meses.length;
    for (var i = 0; i < meses.length; i++) {
      final mes = meses[i];
      final v = totais[mes]!;
      final real = mostrarReal ? v[0] : 0;
      final proj = mostrarProjetado ? v[1] : 0;
      final x = left + i * passo + (passo - 26) / 2;
      final hReal = areaH * real / escala;
      final hProj = areaH * proj / escala;
      final yBase = top + areaH;
      if (real != 0) canvas.drawRect(Rect.fromLTWH(x, yBase - hReal, 26, hReal), Paint()..color = const Color(0xff2677bd));
      if (proj != 0) canvas.drawRect(Rect.fromLTWH(x, yBase - hReal - hProj, 26, hProj), Paint()..color = const Color(0xffe6a23c));
      if (mes == selecionado) canvas.drawRect(Rect.fromLTWH(x - 2, yBase - hReal - hProj - 2, 30, hReal + hProj + 4),
        Paint()..color = const Color(0xff444444)..style = PaintingStyle.stroke..strokeWidth = 1);
      escrever('${mes.substring(5)}/${mes.substring(2,4)}', x - 5, size.height - 25);
    }
  }

  @override
  bool shouldRepaint(covariant _PintorBarrasEmpilhadas old) => true;
}
