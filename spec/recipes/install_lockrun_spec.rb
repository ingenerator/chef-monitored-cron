require 'spec_helper'

describe 'monitored-cron::install_lockrun' do
  cached (:chef_run) do
    ChefSpec::SoloRunner.new do |node|
      # Set non-standard attributes to check the recipe is using the attributes
      node.normal['monitored_cron']['src_dir'] = '/usr/local/othersrc/lockrun'
    end.converge(described_recipe)
  end

  before(:each) do
    stub_command('which lockrun').and_return(true)
  end

  it 'copies the lockrun.c source file to the source dir' do
    expect(chef_run).to create_cookbook_file('/usr/local/othersrc/lockrun/lockrun.c').with(
      owner: 'root',
      group: 'root',
      mode: 0o644
    )
  end

  context 'when lockrun is installed already' do
    before(:each) do
      stub_command('which lockrun').and_return(true)
    end

    it 'does not compile' do
      expect(chef_run).not_to run_execute('gcc lockrun.c -o lockrun')
    end
  end

  context 'when lockrun is not installed' do
    before(:each) do
      stub_command('which lockrun').and_return(false)
    end

    cached (:chef_run) do
      ChefSpec::SoloRunner.new do |node|
        # Set non-standard attributes to check the recipe is using the attributes
        node.normal['monitored_cron']['src_dir'] = '/usr/local/othersrc/lockrun'
      end.converge(described_recipe)
    end

    it 'compiles lockrun from source' do
      expect(chef_run).to run_execute('gcc lockrun.c -o lockrun').with(
        cwd: '/usr/local/othersrc/lockrun',
        user: 'root'
      )
    end
  end

  it 'links the executable from /usr/local/bin' do
    expect(chef_run).to create_link('/usr/local/bin/lockrun').with(
      to: '/usr/local/othersrc/lockrun/lockrun'
    )
  end
end
