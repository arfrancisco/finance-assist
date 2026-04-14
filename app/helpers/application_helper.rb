module ApplicationHelper
  def nav_link_class(path)
    active = current_page?(path)
    base = "text-sm font-medium px-1 py-3 border-b-2 "
    active ? base + "border-blue-500 text-blue-600" : base + "border-transparent text-gray-500 hover:text-gray-700"
  end
end
