require 'chefspec'
require 'chefspec/berkshelf'

RSpec.configure do |c|
  c.filter_run(focus: true)
  c.run_all_when_everything_filtered = true

  # Default platform / version to mock Ohai data from
  c.platform = 'ubuntu'
  c.version = '14.04'

  c.alias_example_group_to :describe_resource, describe_resource: true
end

shared_context 'describe_resource', :describe_resource do
  let (:resource) do
    raise 'Define a `let(:resource)` in your describe_resource block'
  end

  let (:chef_runner) do
    ChefSpec::SoloRunner.new(
      cookbook_path: %w(./test/cookbooks ../),
      step_into:     [resource]
    ) do |node|
      node_attributes.each do |key, values|
        node.normal[key] = values
      end
    end
  end

  let (:converge_what)   { ["test_helpers::test_#{resource}"] }
  let (:node_attributes) { {} }

  let (:chef_run) do
    chef_runner.converge(*converge_what)
  end
end
