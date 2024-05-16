# frozen_string_literal: true

require "octokit"
require "yaml"

class Prog::Test::GithubRunnerGroup < Prog::Test::Base
  FAIL_CONCLUSIONS = ["action_required", "cancelled", "failure", "skipped", "stale", "timed_out"]
  IN_PROGRESS_CONCLUSIONS = ["in_progress", "queued", "requested", "waiting", "pending", "neutral"]

  def self.assemble(vm_host_id, test_cases)

    github_service_project = Project.create(name: "Github Runner Service Project") { _1.id = Config.github_runner_service_project_id}
    github_service_project.associate_with_project(github_service_project)

    github_test_project = Project.create_with_id(name: "Github Runner Test Project")
    GithubInstallation.create_with_id(
      installation_id: Config.github_test_installation_id,
      name: "GithubTestInstallationName",
      type: "GithubTestInstallationType",
      project_id: github_test_project.id
    )
    github_test_project.associate_with_project(github_test_project)

    Strand.create_with_id(
      prog: "Test::GithubRunnerGroup",
      label: "start",
      stack: [{
        "vm_host_id" => vm_host_id,
        "test_cases" => test_cases,
        "github_service_project_id" => github_service_project.id,
        "github_test_project_id" => github_test_project.id
      }]
    )
  end

  label def start
    hop_download_boot_images
  end

  label def download_boot_images
    frame["test_cases"].each do |test_case|
      bud Prog::DownloadBootImage, {"subject_id" => vm_host_id, "image_name" => tests[test_case]["image_name"]}
    end

    hop_wait_download_boot_images
  end

  label def wait_download_boot_images
    reap
    hop_trigger_test_runs if leaf?
    VmHost[vm_host_id].sshable.cmd("ls -lah /var/storage/images")
    donate
  end

  label def trigger_test_runs
    test_runs.each do |run|
      trigger_test_run(run["name"], run["workflow_name"], run["branch_name"])
    end

    # To make sure that the remote test runs are triggered
    sleep 30

    hop_check_test_runs
  end

  label def check_test_runs
    test_runs.each do |run|
      conclusion = test_run_conclusion(run["name"], run["workflow_name"], run["branch_name"])
      if FAIL_CONCLUSIONS.include?(conclusion)
        fail_test "Test run for #{run["name"]}, #{run["workflow_name"]}, #{run["branch_name"]} failed with conclusion #{conclusion}"
      elsif IN_PROGRESS_CONCLUSIONS.include?(conclusion) || conclusion.nil?
        nap 15
      end
    end

    hop_finish
  end

  label def finish
    cleanup
    pop "GithubRunnerGroup tests are finished!"
  end

  label def failed
    cleanup
    nap 15
  end

  def trigger_test_run(repo_name, workflow_name, branch_name)
    url = "repos/#{repo_name}/actions/workflows/#{workflow_name}/dispatches"
    payload = { ref: branch_name }

    begin
      response = client.post(url, payload)
    rescue Octokit::Error => e
      fail_test "Can not trigger workflow for #{repo_name}, #{workflow_name}, #{branch_name} due to #{e.message}"
    end
  end

  def test_run_conclusion(repo_name, workflow_name, branch_name)
    run_id = get_latest_run_id(repo_name, workflow_name, branch_name)
    get_run_conclusion(repo_name, run_id)
  end

  # Function to get the latest workflow run ID
  def get_latest_run_id(repo_name, workflow_name, branch)
    runs = client.workflow_runs("#{repo_name}", workflow_name, { branch: branch })
    latest_run = runs[:workflow_runs].first
    latest_run[:id]
  end

  # Function to check the status of a workflow run
  def get_run_conclusion(repo_name, run_id)
    run = client.workflow_run("#{repo_name}", run_id)
    return run[:conclusion]
  end

  def cleanup
    Project[frame["github_service_project_id"]]&.destroy
    Project[frame["github_test_project_id"]]&.destroy
    cancel_test_runs
  end

  def cancel_test_runs
    test_runs.each do |run|
      cancel_test_run(run["name"], run["workflow_name"], run["branch_name"])
    end
  end

  def cancel_test_run(repo_name, workflow_name, branch_name)
    run_id = get_latest_run_id(repo_name, workflow_name, branch_name)
    begin
      response = client.cancel_workflow_run(repo_name, run_id)
    rescue
      puts "Workflow run #{run_id} for #{repo_name} has already been finished"
    end
  end

  def tests
    @@tests ||= YAML.load_file("config/github_runner_e2e_tests.yml").to_h { [_1["name"], _1] }
  end

  def test_runs
     @@test_runs ||= frame["test_cases"].flat_map { tests[_1]["runs"] }
  end

  def vm_host_id
    @@vm_host_id ||= frame["vm_host_id"] || VmHost.first.id
  end

  def client
    @@client ||= Octokit::Client.new(access_token: Config.github_test_personal_access_token)
  end
end
