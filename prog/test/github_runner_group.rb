# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "yaml"

class Prog::Test::GithubRunnerGroup < Prog::Test::Base
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
      label: "start"
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
    hop_wait_download_boot_images
  end

  label def wait_download_boot_images
    reap
    hop_trigger_remote_test_runs if leaf?
    vm_host.sshable.cmd("ls -lah /var/storage/images")
    donate
  end

  label def trigger_remote_test_runs
    frame["test_cases"].each do |test_case|
      remote_test_runs = tests[test_case]["remote_runs"]
      remote_test_runs.each do |remote_run|
        trigger_remote_test_run(remote_run["name"], remote_run["workflow_name"], remote_run["branch_name"])
      end
    end

    hop_check_remote_test_runs
  end

  label def check_remote_test_runs
    sleep 240
    hop_finish
  end

  label def finish
    Project[frame["github_service_project_id"]].destroy
    Project[frame["github_test_project_id"]].destroy
    pop "VmGroup tests finished!"
  end

  # TODO: Control the request response and fail if necessary
  def trigger_remote_test_run(repo_name, workflow_name, branch_name)
    url = URI("https://api.github.com/repos/#{repo_name}/actions/workflows/#{workflow_name}/dispatches")

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(url)
    request["Authorization"] = "token #{Config.github_test_personal_access_token}"
    request.body = {ref: branch_name}.to_json
    http.request(request)
  end

  def self.tests
    @@tests ||= YAML.load_file("config/github_runner_e2e_tests.yml").to_h { [_1["name"], _1] }
  end

  def vm_host_id
    @@vm_host_id ||= frame["vm_host_id"] || VmHost.first.id
  end
end
