import 'package:flutter/material.dart';
import '../../core/theme.dart';

class ExamDetailScreen extends StatefulWidget {
  final Map<String, dynamic> examResult;
  const ExamDetailScreen({super.key, required this.examResult});

  @override
  State<ExamDetailScreen> createState() => _ExamDetailScreenState();
}

class _ExamDetailScreenState extends State<ExamDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  late List<Map<String, dynamic>> _questions;
  late List<Map<String, dynamic>> _wrong;
  late List<Map<String, dynamic>> _correct;

  @override
  void initState() {
    super.initState();
    _questions = List<Map<String, dynamic>>.from(
        widget.examResult['questions'] ?? []);
    _wrong = _questions.where((q) => q['is_correct'] != 1).toList();
    _correct = _questions.where((q) => q['is_correct'] == 1).toList();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  double get _score {
    if (_questions.isEmpty) return 0;
    return (_correct.length / _questions.length) * 100;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      appBar: AppBar(
        backgroundColor: AppTheme.bgColor,
        title: Text(
          widget.examResult['subject_name'] ?? 'পরীক্ষার বিস্তারিত',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: Colors.white38,
          indicatorColor: AppTheme.primaryColor,
          tabs: [
            Tab(text: 'সব (${_questions.length})'),
            Tab(text: '✅ সঠিক (${_correct.length})'),
            Tab(text: '❌ ভুল (${_wrong.length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildScoreBar(),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildList(_questions),
                _buildList(_correct),
                _buildList(_wrong),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreBar() {
    final isGood = _score >= 70;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        border: const Border(bottom: BorderSide(color: Color(0xFF2A2A3E))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.examResult['chapter_name'] ?? ''} • পৃষ্ঠা: ${widget.examResult['page_numbers'] ?? '-'}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                Text(
                  widget.examResult['exam_date'] ?? '',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Text(
                '${_score.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: isGood ? Colors.green : Colors.red,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${_correct.length}/${_questions.length} সঠিক',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> questions) {
    if (questions.isEmpty) {
      return const Center(
        child: Text('কোনো প্রশ্ন নেই', style: TextStyle(color: Colors.white38)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: questions.length,
      itemBuilder: (ctx, i) => _buildQuestionCard(i + 1, questions[i]),
    );
  }

  Widget _buildQuestionCard(int num, Map<String, dynamic> q) {
    final isCorrect = q['is_correct'] == 1;
    final userAns = q['user_answer'] as String?;
    final correctAns = q['correct_answer'] as String? ?? 'A';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCorrect
              ? Colors.green.withOpacity(0.25)
              : Colors.red.withOpacity(0.25),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isCorrect
                  ? Colors.green.withOpacity(0.08)
                  : Colors.red.withOpacity(0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isCorrect ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Q$num',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isCorrect ? Icons.check_circle : Icons.cancel,
                  color: isCorrect ? Colors.green : Colors.red,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  isCorrect ? 'সঠিক' : 'ভুল',
                  style: TextStyle(
                    color: isCorrect ? Colors.green : Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  'পৃষ্ঠা ${q['page_number'] ?? '-'}',
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          // Question text
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text(
              q['question'] ?? '',
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, height: 1.5),
            ),
          ),
          // Options
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Column(
              children: ['A', 'B', 'C', 'D'].map((opt) {
                final key = 'option_${opt.toLowerCase()}';
                final optText = q[key] as String? ?? '';
                if (optText.isEmpty) return const SizedBox.shrink();

                final isUserAnswer = userAns == opt;
                final isCorrectAnswer = correctAns == opt;

                Color bgColor = Colors.transparent;
                Color borderColor = Colors.white.withOpacity(0.06);
                Color textColor = Colors.white70;
                IconData? trailIcon;

                if (isCorrectAnswer) {
                  bgColor = Colors.green.withOpacity(0.12);
                  borderColor = Colors.green.withOpacity(0.4);
                  textColor = Colors.green.shade300;
                  trailIcon = Icons.check_circle;
                }
                if (isUserAnswer && !isCorrect) {
                  bgColor = Colors.red.withOpacity(0.1);
                  borderColor = Colors.red.withOpacity(0.4);
                  textColor = Colors.red.shade300;
                  trailIcon = Icons.cancel;
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: isCorrectAnswer
                              ? Colors.green
                              : isUserAnswer && !isCorrect
                                  ? Colors.red
                                  : Colors.white12,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Center(
                          child: Text(opt,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(optText,
                            style:
                                TextStyle(color: textColor, fontSize: 13)),
                      ),
                      if (trailIcon != null)
                        Icon(trailIcon,
                            color: isCorrectAnswer ? Colors.green : Colors.red,
                            size: 16),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          // Explanation
          if ((q['explanation'] ?? '').toString().isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: Colors.amber.withOpacity(0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💡 ', style: TextStyle(fontSize: 14)),
                  Expanded(
                    child: Text(
                      q['explanation'],
                      style: const TextStyle(
                          color: Colors.amber, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          // Wrong answer indicator
          if (!isCorrect && userAns != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'তুমি বেছেছিলে: $userAns | সঠিক ছিল: $correctAns',
                  style: const TextStyle(
                      color: Colors.orange, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
