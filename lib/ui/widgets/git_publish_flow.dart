import 'package:flutter/material.dart';

import '../../services/git_service.dart';
import 'git_commit_dialog.dart';

/// 지킬 블로그 폴더의 변경 사항을 git add / commit / push 하는 공통 흐름.
///
/// 성공 여부를 돌려준다. 사용자 취소는 `false`.
Future<bool> runGitPublishFlow(BuildContext context, String jekyllPath) async {
  final messenger = ScaffoldMessenger.of(context);

  if (jekyllPath.isEmpty) {
    messenger.showSnackBar(const SnackBar(
      content: Text('Jekyll 블로그 경로가 설정되지 않았습니다.'),
      backgroundColor: Colors.orange,
    ));
    return false;
  }

  try {
    final gitService = GitService(repoPath: jekyllPath);
    final gitStatus = await gitService.getStatus();

    if (!gitStatus.hasChanges) {
      messenger.showSnackBar(const SnackBar(
        content: Text('변경된 파일이 없습니다.'),
        backgroundColor: Colors.blue,
      ));
      return false;
    }

    final addedPosts = await gitService.getAddedPosts();
    if (!context.mounted) return false;

    final commitMessage = await showDialog<String>(
      context: context,
      builder: (context) => GitCommitDialog(gitStatus: gitStatus, addedPosts: addedPosts),
    );
    if (commitMessage == null) return false;

    messenger.showSnackBar(const SnackBar(
      content: Text('GitHub에 업로드 중...'),
      backgroundColor: Colors.blue,
    ));

    final result = await gitService.addCommitPush(commitMessage);
    if (!context.mounted) return result.success;

    if (result.success) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 12),
              Text('업로드 성공'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.message),
              if (result.addedPosts.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('추가된 포스트', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...result.addedPosts.map((post) => Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 4),
                      child: Text('• $post'),
                    )),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('확인')),
          ],
        ),
      );
      return true;
    }

    messenger.showSnackBar(SnackBar(content: Text(result.message), backgroundColor: Colors.red));
    return false;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('오류 발생: $e'), backgroundColor: Colors.red));
    return false;
  }
}
