# frozen_string_literal: true

class CloverWeb
  hash_branch(:webhook_prefix, "github") do |r|
    r.post true do
      body = r.body.read
      puts "7777777777777777777777777"
      puts body
      puts "7777777777777777777777777"
      unless check_signature(r.headers["x-hub-signature-256"], body)
        response.status = 401
        r.halt
      end

      response.headers["Content-Type"] = "application/json"

      data = JSON.parse(body)
      case r.headers["x-github-event"]
      when "installation"
        return handle_installation(data)
      when "workflow_job"
        return handle_workflow_job(data)
      end

      return error("Unhandled event")
    end
  end

  def error(msg)
    {error: {message: msg}}.to_json
  end

  def success(msg)
    {message: msg}.to_json
  end

  def check_signature(signature, body)
    return false unless signature
    method, actual_digest = signature.split("=")
    expected_digest = OpenSSL::HMAC.hexdigest(method, Config.gh_app_webhook_secret, body)
    Rack::Utils.secure_compare(actual_digest, expected_digest)
  end

  def handle_installation(data)
    installation = GithubInstallation[installation_id: data["installation"]["id"]]
    case data["action"]
    when "deleted"
      unless installation
        return error("Unregistered installation")
      end
      installation.runners.each(&:incr_destroy)
      installation.repositories.each(&:incr_destroy)
      installation.destroy
      return success("GithubInstallation[#{installation.ubid}] deleted")
    end

    error("Unhandled installation action")
  end

  def handle_workflow_job(data)
    puts "6161616161616161616161616161"
    puts data.inspect
    puts "6161616161616161616161616161"
    unless (installation = GithubInstallation[installation_id: data["installation"]["id"]])
      puts "646464646464646464646464646464"
      return error("Unregistered installation")
    end

    puts "656565656565656565656565656565"
    unless (job = data["workflow_job"])
      Clog.emit("No workflow_job in the payload") { {workflow_job_missing: {installation_id: installation.id, action: data["action"]}} }
      return error("No workflow_job in the payload")
    end

    unless (label = job.fetch("labels").find { Github.runner_labels.key?(_1) })
      puts "7676767676767676767676767676767"
      puts label
      return error("Unmatched label")
    end

    if Github.runner_labels[label]["gpu"] && !installation.project.get_ff_enable_gpu_runners
      return error("GPU runners are not enabled for this project")
    end

    if data["action"] == "queued"
      puts "79797979797979797979797979797979"
      puts installation.inspect
      puts label
      puts "82828282828282828282828282828282"
      st = Prog::Vm::GithubRunner.assemble(
        installation,
        repository_name: data["repository"]["full_name"],
        label: label
      )
      runner = GithubRunner[st.id]

      return success("GithubRunner[#{runner.ubid}] created")
    end

    unless (runner_id = job.fetch("runner_id"))
      return error("A workflow_job without runner_id")
    end

    runner = GithubRunner.first(
      installation_id: installation.id,
      repository_name: data["repository"]["full_name"],
      runner_id: runner_id
    )

    return error("Unregistered runner") unless runner

    runner.update(workflow_job: job.except("steps"))

    case data["action"]
    when "in_progress"
      puts "11111121212121111111111212111"
      runner.log_duration("runner_started", Time.parse(job["started_at"]) - Time.parse(job["created_at"]))
      success("GithubRunner[#{runner.ubid}] picked job #{job.fetch("id")}")
    when "completed"
      runner.incr_destroy

      success("GithubRunner[#{runner.ubid}] deleted")
    else
      error("Unhandled workflow_job action")
    end
  end
end
