import 'dart:io';

/// Git 작업을 처리하는 서비스
class GitService {
  final String repoPath;

  GitService({required this.repoPath});

  /// Git 명령어 실행
  Future<ProcessResult> _runGitCommand(List<String> args) async {
    return await Process.run(
      'git',
      ['-c', 'core.quotepath=false', ...args],  // 한글 파일명 올바르게 표시
      workingDirectory: repoPath,
      runInShell: true,
    );
  }

  /// Git 상태 확인
  Future<GitStatus> getStatus() async {
    try {
      final result = await _runGitCommand(['status', '--porcelain']);

      if (result.exitCode != 0) {
        throw Exception('Git status failed: ${result.stderr}');
      }

      final lines = (result.stdout as String).split('\n').where((line) => line.isNotEmpty).toList();

      final staged = <String>[];
      final unstaged = <String>[];
      final untracked = <String>[];

      for (final line in lines) {
        if (line.length < 3) continue;

        final status = line.substring(0, 2);
        final filePath = line.substring(3).trim();

        if (status.startsWith('??')) {
          untracked.add(filePath);
        } else if (status[0] != ' ') {
          staged.add(filePath);
        } else {
          unstaged.add(filePath);
        }
      }

      return GitStatus(
        staged: staged,
        unstaged: unstaged,
        untracked: untracked,
      );
    } catch (e) {
      throw Exception('Failed to get git status: $e');
    }
  }

  /// 추가된 포스트 목록 가져오기
  Future<List<String>> getAddedPosts() async {
    try {
      final status = await getStatus();
      final allChanges = [...status.staged, ...status.unstaged, ...status.untracked];

      // _posts 폴더의 .md 파일만 필터링
      final posts = allChanges
          .where((file) => file.startsWith('_posts/') && file.endsWith('.md'))
          .toList();

      return posts;
    } catch (e) {
      throw Exception('Failed to get added posts: $e');
    }
  }

  /// Git add .
  Future<void> addAll() async {
    try {
      final result = await _runGitCommand(['add', '.']);

      if (result.exitCode != 0) {
        throw Exception('Git add failed: ${result.stderr}');
      }
    } catch (e) {
      throw Exception('Failed to add files: $e');
    }
  }

  /// Git commit
  Future<void> commit(String message) async {
    try {
      final result = await _runGitCommand(['commit', '-m', message]);

      if (result.exitCode != 0) {
        throw Exception('Git commit failed: ${result.stderr}');
      }
    } catch (e) {
      throw Exception('Failed to commit: $e');
    }
  }

  /// Git push
  Future<String> push() async {
    try {
      final result = await _runGitCommand(['push']);

      if (result.exitCode != 0) {
        // Push 실패시 에러 메시지 반환
        throw Exception('Git push failed: ${result.stderr}');
      }

      return result.stdout as String;
    } catch (e) {
      throw Exception('Failed to push: $e');
    }
  }

  /// Git pull
  Future<void> pull() async {
    try {
      final result = await _runGitCommand(['pull']);

      if (result.exitCode != 0) {
        throw Exception('Git pull failed: ${result.stderr}');
      }
    } catch (e) {
      throw Exception('Failed to pull: $e');
    }
  }

  /// 현재 브랜치 이름 가져오기
  Future<String> getCurrentBranch() async {
    try {
      final result = await _runGitCommand(['branch', '--show-current']);

      if (result.exitCode != 0) {
        throw Exception('Failed to get current branch: ${result.stderr}');
      }

      return (result.stdout as String).trim();
    } catch (e) {
      throw Exception('Failed to get current branch: $e');
    }
  }

  /// Git 전체 워크플로우: add -> commit -> push
  Future<GitPushResult> addCommitPush(String commitMessage) async {
    try {
      // 1. 변경된 파일 확인
      final status = await getStatus();
      final addedPosts = await getAddedPosts();

      if (status.staged.isEmpty && status.unstaged.isEmpty && status.untracked.isEmpty) {
        return GitPushResult(
          success: false,
          message: '변경된 파일이 없습니다.',
          addedPosts: [],
        );
      }

      // 2. Git add
      await addAll();

      // 3. Git commit
      await commit(commitMessage);

      // 4. Git push
      final pushOutput = await push();

      return GitPushResult(
        success: true,
        message: '성공적으로 푸시되었습니다.',
        addedPosts: addedPosts,
        pushOutput: pushOutput,
      );
    } catch (e) {
      return GitPushResult(
        success: false,
        message: '푸시 실패: $e',
        addedPosts: [],
      );
    }
  }
}

/// Git 상태 정보
class GitStatus {
  final List<String> staged;
  final List<String> unstaged;
  final List<String> untracked;

  GitStatus({
    required this.staged,
    required this.unstaged,
    required this.untracked,
  });

  bool get hasChanges => staged.isNotEmpty || unstaged.isNotEmpty || untracked.isNotEmpty;

  int get totalChanges => staged.length + unstaged.length + untracked.length;
}

/// Git Push 결과
class GitPushResult {
  final bool success;
  final String message;
  final List<String> addedPosts;
  final String? pushOutput;

  GitPushResult({
    required this.success,
    required this.message,
    required this.addedPosts,
    this.pushOutput,
  });
}
