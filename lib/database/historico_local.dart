part of '../main.dart';

// Persistência local, sem dependências externas adicionais.
// Guarda apenas faturas conciliadas. O PDF original não é copiado.
class HistoricoLocal {
  static Future<File> _arquivo() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/historico_faturas_v1.json');
  }

  static Future<List<Map<String, dynamic>>> listar() async {
    final arquivo = await _arquivo();
    if (!await arquivo.exists()) return [];
    final raw = jsonDecode(await arquivo.readAsString());
    if (raw is! List) throw const FormatException('Histórico inválido');
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static String _identificador(ResultadoFatura r) {
    // Não usa nome do arquivo; ordenação canônica evita diferença na ordem
    // de leitura do PDF. Não depende de arredondamento de double serializado.
    final compras = r.compras.map((e) => [
      e.data.trim(), ParserItau.chave(e.descricao),
      ParserItau.centavos(e.valor), e.parcelaAtual, e.totalParcelas,
    ].join('|')).toList()..sort();
    return jsonEncode([
      r.cartao.trim(), r.vencimento.trim(),
      ParserItau.centavos(r.totalFatura ?? 0),
      ParserItau.centavos(r.totalCartaoInformado ?? 0),
      compras,
    ]);
  }

  static Map<String, dynamic> _lancamento(Lancamento e) => {
    'data': e.data, 'descricao': e.descricao, 'categoria': e.categoria,
    'valorCentavos': ParserItau.centavos(e.valor),
    'parcelaAtual': e.parcelaAtual, 'totalParcelas': e.totalParcelas,
    'tipo': e.tipo, 'observacoes': e.observacoes,
  };

  static Future<bool> salvar(FaturaProcessada f) async {
    if (!f.resultado.conciliada) return false;
    final historico = await listar();
    final id = _identificador(f.resultado);
    if (historico.any((e) => e['id'] == id)) return false;
    final r = f.resultado;
    historico.add({
      'id': id,
      'arquivo': f.arquivo,
      'salvoEm': DateTime.now().toIso8601String(),
      'cartao': r.cartao,
      'vencimento': r.vencimento,
      'totalCentavos': ParserItau.centavos(r.totalFatura ?? 0),
      'subtotalCartaoCentavos': ParserItau.centavos(r.totalCartaoInformado ?? 0),
      'estrategia': r.estrategia,
      'status': r.status,
      'compras': r.compras.map(_lancamento).toList(),
      'lancamentos': r.lancamentos.map(_lancamento).toList(),
    });
    await _gravar(historico);
    return true;
  }

  static Future<void> excluir(String id) async {
    final historico = await listar();
    historico.removeWhere((e) => e['id'] == id);
    await _gravar(historico);
  }

  static Future<void> _gravar(List<Map<String, dynamic>> dados) async {
    final arquivo = await _arquivo();
    final temporario = File('${arquivo.path}.tmp');
    await temporario.writeAsString(jsonEncode(dados), flush: true);
    // Substituição atômica quando suportada pelo sistema de arquivos.
    await temporario.rename(arquivo.path);
  }
}
