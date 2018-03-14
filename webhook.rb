require 'net/http'
require 'uri'
require 'json'
require 'sinatra'

use Rack::Logger
set :bind, '0.0.0.0'

post '/hQMLJxHEB4nKufZpkMkh' do
  request.body.rewind
  data    = JSON.parse(request.body.read)
  gh_user = data['result']['extra_info2_answer']

  halt 400 unless gh_user

  # Create new app
  i = 0
  while i < 5
    res = distelli_call(%(apps/endorsed_candidate), 'PUT')

    case res.code.to_i
    when 200
      logger.info 'Application created'
      i += 5
    when 400
      # Wait if the application already exists
      raise res.body unless JSON.parse(res.body)['error']['code'] == 'AppExists'
      logger.info 'Instance of app exists.  Waiting...'
      sleep 10
      i += 1
    else
      raise res.code
    end
  end
  raise res.body unless res.code.to_i == 200

  # Connect repo
  repo_data = {
    'repo_name'         => 'skillbuilder-deployer',
    'repo_owner'        => 'puppetlabs',
    'repo_provider'     => 'GITHUB',
    'branch'            => 'master',
    'auto_build'        => false,
    'build_server_type' => 'SHARED',
    'build_vars' => [{
      'Name'  => 'DISTELLI_MANIFEST',
      'Value' => 'candidate-manifest.yml',
    }, {
      'Name'  => 'SB_USERNAME',
      'Value' => gh_user,
    }, {
      'Name'  => 'SB_REPO',
      'Value' => sb_repo,
    }, {
      'Name'  => 'SB_TOKEN',
      'Value' => sb_token,
    }],
  }
  res = distelli_call('apps/endorsed_candidate/repo', 'PUT', repo_data)
  raise res.body unless res.code.to_i == 200
  logger.info 'Connected repo'

  # Kickoff build
  res = distelli_call('apps/puppet_endorsed/master/build', 'PUT')
  raise res.body unless res.code.to_i == 200
  logger.info 'Triggered build'

  # Remove app
  res = distelli_call(%(apps/endorsed_candidate), 'DELETE')
  raise res.code unless res.code.to_i == 204
  logger.info 'Deleted application'

  # Using Deploys as the workflow
  # # Create new environment
  # env_data = {
  #   'description' => 'Temporary skillbuilder environment',
  #   'tags'        => ['skillbuilder'],
  #   'vars'        => [{ 'USERNAME' => gh_user }],
  # }
  # res = distelli_call(%(apps/puppet_endorsed/envs/#{gh_user}), 'PUT', env_data)
  # raise res.body unless res.code.to_i == 200

  # begin
  #   # Get latest release
  #   res = distelli_call(%(apps/puppet_endorsed/releases), 'GET')
  #   raise res.body unless res.code.to_i == 200
  #   rel = JSON.parse(res.body)['releases'].sort_by { |r| r['created'] }.last

  #   # Add magicslice to environment
  #   server_data = {
  #     'env_name'        => gh_user,
  #     'description'     => 'Temporary skillbuilder environment',
  #     'servers'         => ['d2fcfbf4-8ff4-3d4d-9e2a-fa163e1475fa'],
  #     'action'          => 'add',
  #     'deploy'          => true,
  #     'release_version' => rel['release_version'],
  #   }
  #   res = distelli_call(%(envs/#{gh_user}/servers), 'PATCH', server_data)
  #   raise res.body unless res.code.to_i == 200
  # rescue StandardError => e
  #   raise e.message
  # ensure
  #   # Can't remove environment without "terminating" deployment
  #   # terminate_data = {
  #   #   'env_name' => gh_user,
  #   # }
  #   # res = distelli_call(%(envs/#{gh_user}/terminate), 'POST', terminate_data)
  #   # raise res.body unless res.code.to_i == 200

  #   # Need to empty servers
  #   server_data = {
  #     'env_name'        => gh_user,
  #     'servers'         => ['d2fcfbf4-8ff4-3d4d-9e2a-fa163e1475fa'],
  #     'action'          => 'remove',
  #   }
  #   res = distelli_call(%(envs/#{gh_user}/servers), 'PATCH', server_data)
  #   raise res.body unless res.code.to_i == 200

  #   # Remove environment
  #   res = distelli_call(%(envs/#{gh_user}), 'DELETE')
  #   raise res.body unless res.code.to_i == 200
  # end
  'hello world'
end

def token
  ENV['DISTELLI_TOKEN']
end

def sb_repo
  ENV['SB_REPO']
end

def sb_token
  ENV['SB_TOKEN']
end

def distelli_call(endpoint, method, data = {})
  url              = %(https://api.distelli.com/esquared/#{endpoint}?apiToken=#{token})
  uri              = URI(url)
  http             = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl     = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  req              = Net::HTTP.const_get(method.capitalize).new(uri.request_uri)
  req.body         = data.to_json
  req.content_type = 'application/json'

  begin
    res = http.request(req)
  rescue StandardError => e
    raise e.message
  else
    res
  end
end

helpers do
  def logger
    request.logger
  end
end
