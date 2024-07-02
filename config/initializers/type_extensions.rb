class Integer
  def ether
    (self.to_d * 1e18.to_d).to_i
  end
  
  def gwei
    (self.to_d * 1e9.to_d).to_i
  end
end

class Float
  def ether
    (self.to_d * 1e18.to_d).to_i
  end
  
  def gwei
    (self.to_d * 1e9.to_d).to_i
  end
end
