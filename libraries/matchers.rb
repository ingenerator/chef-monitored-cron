if defined?(ChefSpec)
  def create_monitored_cron(resource_name)
    ChefSpec::Matchers::ResourceMatcher.new(:monitored_cron, :create, resource_name)
  end
end
