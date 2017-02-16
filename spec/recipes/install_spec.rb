require 'spec_helper'

describe 'monitored-cron::install' do
  let (:chef_run) do
    ChefSpec::SoloRunner.new do |node|
      # Set non-standard attributes to check the recipe is using the attributes
      node.normal['monitored_cron']['src_dir'] = '/src'
      node.normal['monitored_cron']['job_dir'] = '/jobs'
      node.normal['monitored_cron']['lock_dir'] = '/locks'
    end.converge(described_recipe)
  end

  it 'creates the source directory' do
    expect(chef_run).to create_directory('/src').with(
      owner: 'root',
      group: 'root',
      mode: 0o755,
      recursive: true
    )
  end

  it 'creates a lock directory' do
    expect(chef_run).to create_directory('/locks').with(
      owner: 'root',
      group: 'root',
      mode: 0o722,
      recursive: true
    )
  end

  it 'creates a private jobs directory' do
    expect(chef_run).to create_directory('/jobs').with(
      owner: 'root',
      group: 'root',
      mode: 0o755,
      recursive: true
    )
  end

  it 'installs the ruby wrapper script' do
    expect(chef_run).to create_cookbook_file('/src/monitored_cron.rb').with(
      owner: 'root',
      group: 'root',
      mode:  0o755
    )
  end
end
