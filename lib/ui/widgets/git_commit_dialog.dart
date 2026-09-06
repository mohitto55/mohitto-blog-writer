import 'package:flutter/material.dart';
import '../../services/git_service.dart';

class GitCommitDialog extends StatefulWidget {
  final GitStatus gitStatus;
  final List<String> addedPosts;

  const GitCommitDialog({
    super.key,
    required this.gitStatus,
    required this.addedPosts,
  });

  @override
  State<GitCommitDialog> createState() => _GitCommitDialogState();
}

class _GitCommitDialogState extends State<GitCommitDialog> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalChanges = widget.gitStatus.totalChanges;

    return Dialog(
      child: Container(
        width: 600,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더
                Row(
                  children: [
                    const Icon(Icons.upload, size: 28, color: Colors.blue),
                    const SizedBox(width: 12),
                    const Text(
                      'GitHub 업로드',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),

                // 변경 사항 요약
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '$totalChanges개의 파일이 변경되었습니다.',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 추가된 포스트
                if (widget.addedPosts.isNotEmpty) ...[
                  const Text(
                    '📝 추가된 포스트',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 150),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green[200]!),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: widget.addedPosts.length,
                      itemBuilder: (context, index) {
                        final post = widget.addedPosts[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.article, size: 20, color: Colors.green),
                          title: Text(
                            post,
                            style: const TextStyle(fontSize: 13),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // 모든 변경 파일
                const Text(
                  '📂 변경된 파일',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ...widget.gitStatus.staged.map((file) => _buildFileItem(file, 'Staged', Colors.green)),
                      ...widget.gitStatus.unstaged.map((file) => _buildFileItem(file, 'Modified', Colors.orange)),
                      ...widget.gitStatus.untracked.map((file) => _buildFileItem(file, 'New', Colors.blue)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 커밋 메시지 입력
                const Text(
                  '💬 커밋 메시지',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    hintText: 'Add new posts',
                    border: OutlineInputBorder(),
                    helperText: '변경 내용을 간단히 설명해주세요',
                  ),
                  maxLines: 3,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '커밋 메시지를 입력해주세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // 버튼
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          Navigator.pop(context, _messageController.text.trim());
                        }
                      },
                      icon: const Icon(Icons.upload),
                      label: const Text('업로드'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileItem(String file, String status, Color color) {
    return ListTile(
      dense: true,
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          status,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
      title: Text(
        file,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}
