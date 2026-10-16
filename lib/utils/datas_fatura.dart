part of '../main.dart';

// Datas derivadas para exibição/exportação. Não altera PDFs nem histórico.
class DatasFatura {
  static DateTime? ler(String valor) {
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(valor.trim());
    if (m == null) return null;
    final dia = int.parse(m.group(1)!);
    final mes = int.parse(m.group(2)!);
    final ano = int.parse(m.group(3)!);
    if (ano < 1900 || ano > 2200 || mes < 1 || mes > 12 || dia < 1) return null;
    final d = DateTime(ano, mes, dia);
    return d.year == ano && d.month == mes && d.day == dia ? d : null;
  }

  static String formatar(DateTime? d) => d == null ? '' :
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  // Preserva o dia do vencimento; ajusta apenas meses sem esse dia (ex.: 31/01 -> 28/02).
  static DateTime adicionarMeses(DateTime data, int meses) {
    final primeiro = DateTime(data.year, data.month + meses, 1);
    final ultimoDia = DateTime(primeiro.year, primeiro.month + 1, 0).day;
    return DateTime(primeiro.year, primeiro.month,
        data.day < ultimoDia ? data.day : ultimoDia);
  }

  static String vencimentoParcela(String vencimentoBase, int mesesAFrente) {
    final d = ler(vencimentoBase);
    return formatar(d == null ? null : adicionarMeses(d, mesesAFrente));
  }

  // O Itaú geralmente informa a data original como DD/MM, sem ano.
  // Inferimos o ano tomando por referência o vencimento da primeira parcela.
  // Se não houver base confiável, devolvemos a data original, sem inventar ano.
  static String dataCompra(String original, String vencimento,
      int? parcelaAtual) {
    final texto = original.trim();
    if (ler(texto) != null) return texto;
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})$').firstMatch(texto);
    final v = ler(vencimento);
    if (m == null || v == null) return texto;
    final dia = int.parse(m.group(1)!);
    final mes = int.parse(m.group(2)!);
    if (dia < 1 || mes < 1 || mes > 12) return texto;
    final referencia = adicionarMeses(v, -((parcelaAtual != null && parcelaAtual > 0)
        ? parcelaAtual - 1 : 0));
    DateTime? melhor;
    for (final ano in [referencia.year, referencia.year - 1, referencia.year + 1]) {
      final d = DateTime(ano, mes, dia);
      if (d.month != mes || d.day != dia) continue;
      if (d.isAfter(referencia)) continue;
      if (melhor == null || d.isAfter(melhor)) melhor = d;
    }
    // Distância maior que 120 dias: não atribuir ano sem evidência suficiente.
    if (melhor == null || referencia.difference(melhor).inDays > 120) return texto;
    return formatar(melhor);
  }
}
